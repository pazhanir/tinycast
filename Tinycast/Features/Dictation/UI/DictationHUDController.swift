import AppKit
import SwiftUI

@MainActor
final class DictationHUDController {
    private let presenter: HUDPresenter
    private var currentState: DictationHUDState = .listening
    private var currentLevel: Float = 0.0
    private var providerName: String = ""

    var onStopRequested: (() -> Void)?
    var onCancelRequested: (() -> Void)?

    init(settings: AppSettings) {
        presenter = HUDPresenter(
            anchor: .edgeInset(Theme.Size.hudEdgeOffset),
            dwell: 1.5,
            screen: { settings.openOnCursorScreen ? .underCursor : .primary }
        )
    }

    func show(state: DictationHUDState, providerName: String) {
        self.currentState = state
        self.providerName = providerName
        render(dwells: state == .success)
    }

    func updateAudioLevel(_ level: Float) {
        guard currentState == .listening else { return }
        self.currentLevel = level
        render(dwells: false)
    }

    func dismiss() {
        presenter.dismiss()
    }

    private func render(dwells: Bool) {
        let view = DictationHUDView(
            state: currentState,
            audioLevel: currentLevel,
            providerName: providerName,
            onStop: { [weak self] in
                self?.onStopRequested?()
            },
            onCancel: { [weak self] in
                self?.onCancelRequested?()
            }
        )
        presenter.show(view, dwells: dwells)
    }
}
