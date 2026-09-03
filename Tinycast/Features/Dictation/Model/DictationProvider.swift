import Foundation

enum DictationProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case groq = "groq"
    case onDeviceAppleSpeech = "onDeviceAppleSpeech"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groq:
            return "Groq Whisper (Cloud)"
        case .onDeviceAppleSpeech:
            return "macOS Speech (On-Device)"
        }
    }

    var subtitle: String {
        switch self {
        case .groq:
            return "whisper-large-v3-turbo • Blazing fast, free tier, high accuracy"
        case .onDeviceAppleSpeech:
            return "100% offline, private, zero configuration, no API key needed"
        }
    }

    var defaultModel: String {
        switch self {
        case .groq:
            return "whisper-large-v3-turbo"
        case .onDeviceAppleSpeech:
            return "apple-speech"
        }
    }
}
