import Foundation

/// Pure recognizer for Function (fn / Globe) key interactions: hold-to-talk and press-to-toggle.
struct FnTapDetector: Sendable {
    /// Longest a press may last to be considered a quick tap in toggle mode (400ms).
    static let maxTapDuration: TimeInterval = 0.40

    enum Mode: Sendable {
        case holdToTalk
        case pressToToggle
    }

    enum Input: Sendable {
        case fnFlag(isHeld: Bool, hasOtherModifiers: Bool)
        case otherInput
    }

    enum Output: Equatable, Sendable {
        case none
        case holdBegan
        case holdEnded
        case holdCancelled
        case toggleTriggered
    }

    private var mode: Mode
    private var isFnHeld = false
    private var isCurrentlyHolding = false
    private var pressStartTime: TimeInterval?

    init(mode: Mode = .holdToTalk) {
        self.mode = mode
    }

    mutating func setMode(_ mode: Mode) {
        self.mode = mode
        reset()
    }

    mutating func reset() {
        isFnHeld = false
        isCurrentlyHolding = false
        pressStartTime = nil
    }

    /// Handles a flag change or other keyboard/mouse input at a monotonic timestamp.
    mutating func handle(_ input: Input, at now: TimeInterval) -> Output {
        switch input {
        case .otherInput:
            if isCurrentlyHolding {
                reset()
                return .holdCancelled
            }
            reset()
            return .none

        case .fnFlag(let isHeld, let hasOtherModifiers):
            if hasOtherModifiers {
                if isCurrentlyHolding {
                    reset()
                    return .holdCancelled
                }
                reset()
                return .none
            }

            guard isHeld != isFnHeld else { return .none }
            isFnHeld = isHeld

            switch mode {
            case .holdToTalk:
                if isHeld {
                    isCurrentlyHolding = true
                    pressStartTime = now
                    return .holdBegan
                } else {
                    guard isCurrentlyHolding else {
                        reset()
                        return .none
                    }
                    reset()
                    return .holdEnded
                }

            case .pressToToggle:
                if isHeld {
                    pressStartTime = now
                    return .none
                } else {
                    guard let start = pressStartTime else {
                        reset()
                        return .none
                    }
                    pressStartTime = nil
                    let duration = now - start
                    if duration <= Self.maxTapDuration {
                        return .toggleTriggered
                    }
                    return .none
                }
            }
        }
    }
}
