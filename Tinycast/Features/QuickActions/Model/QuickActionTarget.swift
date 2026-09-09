import Foundation

enum QuickActionTarget: Equatable, Hashable, Sendable {
    case builtIn(QuickAction)
    case custom(CustomQuickAction)

    var title: String {
        switch self {
        case .builtIn(let a): return a.title
        case .custom(let c): return c.name
        }
    }

    var symbol: String {
        switch self {
        case .builtIn(let a): return a.symbol
        case .custom(let c): return c.symbol
        }
    }

    var progressTitle: String {
        switch self {
        case .builtIn(let a): return a.progressTitle
        case .custom(let c): return "Running \(c.name)…"
        }
    }

    var showsDiff: Bool {
        switch self {
        case .builtIn(let a): return a.showsDiff
        case .custom: return false
        }
    }

    var usesTranslationFramework: Bool {
        switch self {
        case .builtIn(let a): return a.usesTranslationFramework
        case .custom: return false
        }
    }

    var builtInAction: QuickAction? {
        if case .builtIn(let action) = self { return action }
        return nil
    }
}
