import Foundation

protocol DictationTranscriptionEngine: Sendable {
    func transcribe(
        wavData: Data,
        prompt: String?,
        language: String?
    ) async throws -> String
}
