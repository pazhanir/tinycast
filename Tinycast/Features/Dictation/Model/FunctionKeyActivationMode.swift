import Foundation

enum FunctionKeyActivationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case holdToTalk = "holdToTalk"
    case pressToToggle = "pressToToggle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdToTalk:
            return "Hold to Talk"
        case .pressToToggle:
            return "Press to Toggle"
        }
    }

    var description: String {
        switch self {
        case .holdToTalk:
            return "Hold the Fn (Globe 🌐) key while speaking, release to transcribe."
        case .pressToToggle:
            return "Press the Fn (Globe 🌐) key once to start recording, press again to stop."
        }
    }
}
