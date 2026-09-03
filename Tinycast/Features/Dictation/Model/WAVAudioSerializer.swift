import Foundation

/// Serializes raw 16-bit mono PCM audio samples into a standard RIFF/WAVE container.
enum WAVAudioSerializer {
    static func createWAVData(pcmData: Data, sampleRate: Int = 16000, channels: Int = 1) -> Data {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let chunkSize = 36 + dataSize

        var header = Data()
        header.reserveCapacity(44 + pcmData.count)

        // RIFF chunk descriptor
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var chunkSizeLE = chunkSize.littleEndian
        header.append(Data(bytes: &chunkSizeLE, count: 4))
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // "fmt " sub-chunk
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        var subchunk1Size: UInt32 = UInt32(16).littleEndian
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = UInt16(1).littleEndian // 1 = PCM
        header.append(Data(bytes: &audioFormat, count: 2))
        var numChannels: UInt16 = UInt16(channels).littleEndian
        header.append(Data(bytes: &numChannels, count: 2))
        var sampleRateLE: UInt32 = UInt32(sampleRate).littleEndian
        header.append(Data(bytes: &sampleRateLE, count: 4))
        var byteRateLE: UInt32 = UInt32(byteRate).littleEndian
        header.append(Data(bytes: &byteRateLE, count: 4))
        var blockAlignLE: UInt16 = UInt16(blockAlign).littleEndian
        header.append(Data(bytes: &blockAlignLE, count: 2))
        var bitsPerSampleLE: UInt16 = UInt16(bitsPerSample).littleEndian
        header.append(Data(bytes: &bitsPerSampleLE, count: 2))

        // "data" sub-chunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var dataSizeLE = dataSize.littleEndian
        header.append(Data(bytes: &dataSizeLE, count: 4))

        // Raw audio samples
        header.append(pcmData)
        return header
    }
}
