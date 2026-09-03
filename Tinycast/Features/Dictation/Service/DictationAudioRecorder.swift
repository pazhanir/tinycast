import AVFoundation
import AppKit

@MainActor
final class DictationAudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var pcmData = Data()
    private(set) var isRecording = false

    /// Normalized audio level from 0.0 to 1.0 for UI waveform rendering
    var onAudioLevel: ((Float) -> Void)?

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording() throws {
        guard !isRecording else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "DictationAudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio input format."])
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "DictationAudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot initialize audio converter."])
        }

        self.audioEngine = engine
        self.audioConverter = converter
        self.pcmData = Data()
        self.pcmData.reserveCapacity(16000 * 2 * 30) // ~30 seconds buffer reservation
        self.isRecording = true

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            self?.processInputBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stopRecording() -> Data {
        guard isRecording else { return Data() }
        isRecording = false

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil

        let recordedPCM = pcmData
        pcmData = Data()
        return recordedPCM
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil
        pcmData = Data()
    }

    // MARK: - Buffer Processing

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecording, let converter = audioConverter else { return }

        // 1. Calculate RMS audio power for waveform UI
        if let channelData = buffer.floatChannelData {
            let channelDataPointer = channelData[0]
            let frameLength = UInt(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<Int(frameLength) {
                let sample = channelDataPointer[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(max(1, frameLength)))
            // Normalize roughly between 0.0 and 1.0 (typical speaking speech RMS is 0.02 - 0.3)
            let normalized = min(1.0, max(0.0, rms * 4.5))

            Task { @MainActor in
                self.onAudioLevel?(normalized)
            }
        }

        // 2. Convert to 16kHz Int16 PCM
        let targetFrameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        ) + 100

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCapacity) else {
            return
        }

        var error: NSError?
        var isEndOfStream = false
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            if isEndOfStream {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            isEndOfStream = true
            return buffer
        }

        if status != .error, outputBuffer.frameLength > 0, let int16Data = outputBuffer.int16ChannelData {
            let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
            let dataChunk = Data(bytes: int16Data[0], count: byteCount)

            Task { @MainActor in
                guard self.isRecording else { return }
                self.pcmData.append(dataChunk)
            }
        }
    }
}
