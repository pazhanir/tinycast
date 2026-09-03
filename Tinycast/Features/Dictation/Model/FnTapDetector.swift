import Foundation

/// Pure recognizer for single, double, or triple taps of the Mac Function (fn / Globe) key.
struct FnTapDetector: Sendable {
    /// Longest a press may last to be considered a quick tap (400ms).
    static let maxHold: TimeInterval = 0.40
    /// Longest gap between successive taps (450ms).
    static let maxGap: TimeInterval = 0.45

    enum Input: Sendable {
        case fnFlag(isHeld: Bool, hasOtherModifiers: Bool)
        case otherInput
    }

    private var targetTaps: Int
    private var isFnHeld = false
    private var pressStartTime: TimeInterval?
    private var lastReleaseTime: TimeInterval?
    private var tapCount: Int = 0

    init(targetTaps: Int = 2) {
        self.targetTaps = targetTaps
    }

    mutating func setTargetTaps(_ taps: Int) {
        self.targetTaps = taps
        reset()
    }

    mutating func reset() {
        isFnHeld = false
        pressStartTime = nil
        lastReleaseTime = nil
        tapCount = 0
    }

    /// Handles a flag or input transition. Returns true when target tap count has been reached.
    mutating func handle(_ input: Input, at now: TimeInterval) -> Bool {
        switch input {
        case .otherInput:
            reset()
            return false

        case .fnFlag(let isHeld, let hasOtherModifiers):
            if hasOtherModifiers {
                reset()
                return false
            }

            guard isHeld != isFnHeld else { return false }
            isFnHeld = isHeld

            if isHeld {
                // Fn key pressed down
                if let lastRelease = lastReleaseTime, now - lastRelease > Self.maxGap {
                    tapCount = 0
                }
                pressStartTime = now
                return false
            } else {
                // Fn key released
                guard let start = pressStartTime else {
                    reset()
                    return false
                }
                pressStartTime = nil
                let duration = now - start
                guard duration <= Self.maxHold else {
                    tapCount = 0
                    return false
                }

                tapCount += 1
                lastReleaseTime = now

                if tapCount >= targetTaps {
                    reset()
                    return true
                }
                return false
            }
        }
    }
}
