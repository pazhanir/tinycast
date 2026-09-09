import Foundation
import Observation

/// Owned by the controller, not the view, so a reply keeps arriving while SwiftUI re-renders.
@MainActor
@Observable
final class QuickActionPanelState {
    enum Phase: Equatable {
        case running
        case finished
        case failed(String)
        /// The pair is supported but not downloaded; only SwiftUI's `translationTask` can fetch it.
        case needsLanguageDownload
    }

    let target: QuickActionTarget
    let original: String
    private(set) var output = ""
    private(set) var phase: Phase = .running
    var targetLanguage: Locale.Language

    var action: QuickAction? { target.builtInAction }

    @ObservationIgnored private var cachedDiff: [TextDiffEngine.Chunk]?

    var diff: [TextDiffEngine.Chunk] {
        guard target.showsDiff, phase == .finished else { return [] }
        if let cachedDiff { return cachedDiff }
        let chunks = TextDiffEngine.diff(original: original, modified: output)
        cachedDiff = chunks
        return chunks
    }

    var isRunning: Bool { phase == .running }

    var canReplace: Bool { phase == .finished && !output.isEmpty }

    init(target: QuickActionTarget, original: String, targetLanguage: Locale.Language) {
        self.target = target
        self.original = original
        self.targetLanguage = targetLanguage
    }

    convenience init(action: QuickAction, original: String, targetLanguage: Locale.Language) {
        self.init(target: .builtIn(action), original: original, targetLanguage: targetLanguage)
    }

    convenience init(customAction: CustomQuickAction, original: String, targetLanguage: Locale.Language) {
        self.init(target: .custom(customAction), original: original, targetLanguage: targetLanguage)
    }

    func append(_ delta: String) {
        output += delta
    }

    func restart() {
        output = ""
        phase = .running
        cachedDiff = nil
    }

    func finish(_ text: String) {
        output = text
        phase = .finished
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }

    func requireLanguageDownload() {
        phase = .needsLanguageDownload
    }
}
