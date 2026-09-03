import Foundation

enum DictationTriggerMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case singleTapFn = "singleTapFn"
    case doubleTapFn = "doubleTapFn"
    case tripleTapFn = "tripleTapFn"
    case customShortcut = "customShortcut"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .singleTapFn:
            return "Single Press Fn / Globe (🌐)"
        case .doubleTapFn:
            return "Double Tap Fn / Globe (🌐🌐)"
        case .tripleTapFn:
            return "Triple Tap Fn / Globe (🌐🌐🌐)"
        case .customShortcut:
            return "Custom Keyboard Shortcut"
        }
    }

    var requiredTaps: Int {
        switch self {
        case .singleTapFn: return 1
        case .doubleTapFn: return 2
        case .tripleTapFn: return 3
        case .customShortcut: return 0
        }
    }

    var isFnTrigger: Bool {
        self != .customShortcut
    }
}
