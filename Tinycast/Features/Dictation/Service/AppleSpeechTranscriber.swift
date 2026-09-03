import Foundation
import Speech

struct AppleSpeechTranscriber: DictationTranscriptionEngine {
    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func transcribe(
        wavData: Data,
        prompt: String?,
        language: String?
    ) async throws -> String {
        // Request authorization if needed
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard authStatus == .authorized else {
            throw NSError(
                domain: "AppleSpeechTranscriber",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission is not granted. Please allow in System Settings › Privacy & Security › Speech Recognition."]
            )
        }

        let recognizerLocale: Locale
        if let lang = language?.trimmingCharacters(in: .whitespacesAndNewlines), !lang.isEmpty, lang.lowercased() != "auto" {
            recognizerLocale = Locale(identifier: lang)
        } else {
            recognizerLocale = locale
        }

        guard let recognizer = SFSpeechRecognizer(locale: recognizerLocale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            throw NSError(
                domain: "AppleSpeechTranscriber",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No speech recognizer available for locale \(recognizerLocale.identifier)."]
            )
        }

        guard recognizer.isAvailable else {
            throw NSError(
                domain: "AppleSpeechTranscriber",
                code: 503,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is currently unavailable."]
            )
        }

        // Write WAV data to a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("tinycast_dictation_\(UUID().uuidString).wav")
        try wavData.write(to: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // Add contextual strings from prompt if available (names, vocabulary)
        if let prompt {
            var contextualTerms: [String] = []
            let words = prompt.components(separatedBy: CharacterSet(charactersIn: ",:\n\r\t "))
            for w in words {
                let trimmed = w.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 2 && !contextualTerms.contains(trimmed) {
                    contextualTerms.append(trimmed)
                    if contextualTerms.count >= 50 { break }
                }
            }
            request.contextualStrings = contextualTerms
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = RecognitionSession(continuation: continuation)
            let task = recognizer.recognitionTask(with: request) { result, error in
                session.handleResult(result: result, error: error)
            }
            session.attachTask(task)

            Task {
                try? await Task.sleep(for: .seconds(10))
                session.handleTimeout()
            }
        }
    }
}

private final class RecognitionSession: @unchecked Sendable {
    private let lock = NSLock()
    private var isCompleted = false
    private var finalTranscript = ""
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String, Error>?

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func attachTask(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        defer { lock.unlock() }
        self.task = task
    }

    func handleResult(result: SFSpeechRecognitionResult?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCompleted else { return }

        if let error {
            isCompleted = true
            let continuation = self.continuation
            self.continuation = nil
            if !finalTranscript.isEmpty {
                continuation?.resume(returning: finalTranscript)
            } else {
                continuation?.resume(throwing: error)
            }
            return
        }

        if let result {
            finalTranscript = result.bestTranscription.formattedString
            if result.isFinal {
                isCompleted = true
                let continuation = self.continuation
                self.continuation = nil
                continuation?.resume(returning: finalTranscript)
            }
        }
    }

    func handleTimeout() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCompleted else { return }
        isCompleted = true
        task?.cancel()
        let continuation = self.continuation
        self.continuation = nil
        if !finalTranscript.isEmpty {
            continuation?.resume(returning: finalTranscript)
        } else {
            continuation?.resume(throwing: NSError(
                domain: "AppleSpeechTranscriber",
                code: 408,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition timed out."]
            ))
        }
    }
}
