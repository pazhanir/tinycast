import AppKit
import Carbon.HIToolbox

private func fnTapEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<FnTapMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { monitor.tapWasDisabled() }
        return Unmanaged.passUnretained(event)
    }

    let isFlagsChanged = type == .flagsChanged
    let flagsRaw = event.flags.rawValue
    MainActor.assumeIsolated {
        monitor.process(isFlagsChanged: isFlagsChanged, flagsRaw: flagsRaw)
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
final class FnTapMonitor: HealthCheckable {
    var onHoldBegan: (() -> Void)?
    var onHoldEnded: (() -> Void)?
    var onHoldCancelled: (() -> Void)?
    var onToggle: (() -> Void)?

    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            detector.reset()
        }
    }

    private var isEnabled = false
    private var detector = FnTapDetector(mode: .holdToTalk)
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var sessionTokens: [NotificationToken] = []
    private var sessionActive = true

    weak var healthTicker: HealthTicker?

    isolated deinit {
        tearDownTap()
    }

    func update(enabled: Bool, mode: FunctionKeyActivationMode) {
        self.isEnabled = enabled
        self.detector.setMode(mode == .holdToTalk ? .holdToTalk : .pressToToggle)
        installObserversIfNeeded()
        syncTapPresence()
    }

    fileprivate func process(isFlagsChanged: Bool, flagsRaw: UInt64) {
        guard !isPaused, isEnabled, sessionActive else { return }
        let now = ProcessInfo.processInfo.systemUptime

        let input: FnTapDetector.Input
        if isFlagsChanged {
            let flags = CGEventFlags(rawValue: flagsRaw)
            let isFnHeld = flags.contains(.maskSecondaryFn)
            let hasOtherModifiers = flags.contains(.maskControl)
                || flags.contains(.maskAlternate)
                || flags.contains(.maskShift)
                || flags.contains(.maskCommand)
            input = .fnFlag(isHeld: isFnHeld, hasOtherModifiers: hasOtherModifiers)
        } else {
            input = .otherInput
        }

        switch detector.handle(input, at: now) {
        case .none:
            break
        case .holdBegan:
            onHoldBegan?()
        case .holdEnded:
            onHoldEnded?()
        case .holdCancelled:
            onHoldCancelled?()
        case .toggleTriggered:
            onToggle?()
        }
    }

    private func installObserversIfNeeded() {
        guard sessionTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidChange(active: false) }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidChange(active: true) }
                }, center: center)
        ]
    }

    private func sessionDidChange(active: Bool) {
        sessionActive = active
        detector.reset()
        syncTapPresence()
    }

    private func syncTapPresence() {
        guard isEnabled, sessionActive else {
            tearDownTap()
            healthTicker?.unsubscribe(self)
            return
        }
        healthTicker?.subscribe(self)
        installTapIfNeeded()
    }

    private func installTapIfNeeded() {
        guard tapPort == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)

        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .tailAppendEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: fnTapEventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return
        }

        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func tearDownTap() {
        detector.reset()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
            self.tapPort = nil
        }
    }

    fileprivate func tapWasDisabled() {
        detector.reset()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    func healthCheck() {
        guard isEnabled, sessionActive else { return }
        if tapPort == nil {
            installTapIfNeeded()
        } else if !Permissions.isAccessibilityTrusted() {
            tearDownTap()
        } else if let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        }
    }
}
