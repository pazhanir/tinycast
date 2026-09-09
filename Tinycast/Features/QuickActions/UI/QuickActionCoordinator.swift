import AppKit
import Observation

/// The single funnel for every Quick Action, however it was started.
@MainActor
@Observable
final class QuickActionCoordinator {
    private let settings: AppSettings
    private let store: QuickActionSettingsStore
    private let injector: TextInjector
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator
    private let panels = QuickActionPanelController()
    private unowned let core: AppCore

    private static let launcherCommands = Set(QuickAction.allCases.map(CommandID.init))

    /// One at a time: two runs race for one selection, and the second overwrites the first's work.
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(
        settings: AppSettings, store: QuickActionSettingsStore, injector: TextInjector,
        appIndex: AppIndex, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.store = store
        self.injector = injector
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// Launcher rows come and go with the switch; the Carbon bindings stay registered.
    func applyEnabled() {
        appIndex.setCommandsVisible(Self.launcherCommands, settings.quickActionsEnabled)
        guard settings.quickActionsEnabled else {
            cancel()
            core.applyInstalledAILifecycle()
            return
        }
        core.applyInstalledAILifecycle()
        store.resolveModel(
            appleIntelligenceAvailable: core.aiSettings.isAppleIntelligenceAvailable(),
            fallback: core.aiSettings.defaultModel)
        loadLanguages()
    }

    /// Enabling is consent: reading a selection and typing over it both need Accessibility.
    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.quickActionsEnabled else { return }
        guard enabled else {
            settings.quickActionsEnabled = false
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Enable Quick Actions?",
                    message:
                        "Tinycast needs the Accessibility permission to read the text you have "
                        + "selected in other apps and replace it. Nothing is read until you press "
                        + "a shortcut.",
                    symbol: "wand.and.sparkles", confirmTitle: "Continue", tone: .neutral,
                    confirmRole: .standard)
            else { return }
            settings.quickActionsEnabled = true
            // The one prompt for this feature, raised from the gesture that asked for it.
            Permissions.ensureAccessibility()
        }
    }

    func run(_ action: QuickAction) {
        guard settings.quickActionsEnabled, running == nil else { return }
        let target = paletteCoordinator.targetApp
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        start { [weak self] in await self?.begin(action, target: target) }
    }

    func run(_ customAction: CustomQuickAction) {
        guard settings.quickActionsEnabled, running == nil else { return }
        let target = paletteCoordinator.targetApp
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        start { [weak self] in await self?.begin(customAction, target: target) }
    }

    func cancel() {
        generation += 1
        running?.cancel()
        running = nil
        panels.dismiss()
    }

    /// The generation stops a superseded task from clearing the newer handle as it finishes.
    private func start(_ work: @escaping @MainActor () async -> Void) {
        generation += 1
        let mine = generation
        running?.cancel()
        running = Task { [weak self] in
            await work()
            guard let self, mine == self.generation else { return }
            self.running = nil
        }
    }

    private func begin(_ action: QuickAction, target: NSRunningApplication?) async {
        let selection: String
        do {
            selection = try await QuickActionRunner.selection(in: target, using: injector)
        } catch let failure as QuickActionFailure {
            reportRefusal(failure)
            return
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
            return
        }
        let state = QuickActionPanelState(
            action: action, original: selection, targetLanguage: targetLanguage)
        let previews = store.settings.previewsResult(action)
        if previews { present(state, target: target) }
        await perform(state, target: target, previewing: previews)
    }

    private func begin(_ customAction: CustomQuickAction, target: NSRunningApplication?) async {
        let selection: String
        let needsSelection = SnippetTemplateEngine.usesSelection(customAction.prompt)
        if needsSelection {
            do {
                selection = try await QuickActionRunner.selection(in: target, using: injector)
            } catch let failure as QuickActionFailure {
                reportRefusal(failure)
                return
            } catch {
                core.showMessage(error.localizedDescription, tone: .danger)
                return
            }
        } else {
            if let target, let read = try? await QuickActionRunner.selection(in: target, using: injector) {
                selection = read
            } else {
                selection = ""
            }
        }

        if customAction.outputMode == .openInAIChat {
            await performOpenInAIChat(customAction, selection: selection)
            return
        }

        let state = QuickActionPanelState(
            customAction: customAction, original: selection, targetLanguage: targetLanguage)
        let previews = (customAction.outputMode == .previewInPanel)
        if previews { present(state, target: target) }
        await performCustom(state, customAction: customAction, target: target, previewing: previews)
    }

    private func performOpenInAIChat(_ customAction: CustomQuickAction, selection: String) async {
        let declared = SnippetTemplateEngine.declaredArguments(in: customAction.prompt)
        var userArguments: [String: String] = [:]
        if !declared.isEmpty {
            guard let collected = SnippetArgumentsPrompt.run(
                snippetName: customAction.name,
                arguments: declared
            ) else {
                return
            }
            userArguments = collected
        }

        let clipboardHistory = (NSPasteboard.general.string(forType: .string).map { [$0] }) ?? []
        let context = SnippetTemplateEngine.ExpansionContext(
            clipboardHistory: clipboardHistory,
            selection: selection,
            now: Date(),
            calendar: .current,
            locale: .current,
            timeZone: .current
        )
        let expansion = SnippetTemplateEngine.expand(
            text: customAction.prompt,
            context: context,
            userArguments: userArguments
        )

        core.aiChatCoordinator.ask(expansion.text)
    }

    /// A missing permission cannot be fixed from a pill that fades, so it earns a dialog instead.
    private func reportRefusal(_ failure: QuickActionFailure) {
        guard failure.opensAccessibilitySettings else {
            core.showMessage(failure.localizedDescription, tone: .danger)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.reportFailure(
                    title: "Quick Actions can't read your selection",
                    message:
                        "Tinycast needs the Accessibility permission to read the text you have "
                        + "selected and replace it. If Tinycast is already listed, switch it off "
                        + "and on again — a rebuilt app keeps a stale entry.",
                    symbol: "wand.and.sparkles", recovery: "Open System Settings")
            else { return }
            Permissions.openAccessibilitySettings()
        }
    }

    private func perform(
        _ state: QuickActionPanelState, target: NSRunningApplication?, previewing: Bool
    ) async {
        guard let action = state.action else { return }
        do {
            let text = try await produce(state, action: action, previewing: previewing)
            guard !Task.isCancelled else { return }
            state.finish(text)
            if previewing { return }
            deliver(text, to: target, title: state.target.title)
        } catch is CancellationError {
            return
        } catch let error as TextTranslator.Failure where error.needsDownload {
            // Only SwiftUI's `translationTask` can fetch a pair, so this has to become a panel.
            if !previewing { present(state, target: target) }
            state.requireLanguageDownload()
        } catch {
            report(error, state: state, previewing: previewing)
        }
    }

    private func performCustom(
        _ state: QuickActionPanelState, customAction: CustomQuickAction,
        target: NSRunningApplication?, previewing: Bool
    ) async {
        do {
            if !previewing {
                core.showProgress(state.target.progressTitle)
            }
            defer {
                if !previewing {
                    core.hideProgress()
                }
            }

            let declared = SnippetTemplateEngine.declaredArguments(in: customAction.prompt)
            var userArguments: [String: String] = [:]
            if !declared.isEmpty {
                guard let collected = SnippetArgumentsPrompt.run(
                    snippetName: customAction.name,
                    arguments: declared
                ) else {
                    if previewing { cancel() }
                    return
                }
                userArguments = collected
            }

            let clipboardHistory = (NSPasteboard.general.string(forType: .string).map { [$0] }) ?? []
            let context = SnippetTemplateEngine.ExpansionContext(
                clipboardHistory: clipboardHistory,
                selection: state.original,
                now: Date(),
                calendar: .current,
                locale: .current,
                timeZone: .current
            )
            let expansion = SnippetTemplateEngine.expand(
                text: customAction.prompt,
                context: context,
                userArguments: userArguments
            )

            let provider = try core.quickActionProvider(for: customAction.model)
            let request = AIRequest(
                instructions: "You are an AI assistant executing an action. Follow the instructions and respond directly without conversational filler.",
                messages: [AIMessage(role: .user, text: expansion.text)]
            )
            var response = ""
            for try await event in provider.stream(request) {
                guard case .text(let delta) = event else { continue }
                response += delta
                if previewing { state.append(delta) }
            }
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AIProviderError.responseFailed("The model returned nothing.")
            }

            guard !Task.isCancelled else { return }
            state.finish(trimmed)
            if previewing { return }

            switch customAction.outputMode {
            case .previewInPanel:
                break
            case .openInAIChat:
                core.aiChatCoordinator.ask(trimmed)
            case .replaceSelection:
                deliver(trimmed, to: target, title: state.target.title)
            case .copyToClipboard:
                Paster.copyPlainText(trimmed)
                core.showMessage("\(state.target.title): Copied to clipboard")
            case .insertBelow:
                let insertion = state.original.isEmpty ? trimmed : (state.original + "\n\n" + trimmed)
                deliver(insertion, to: target, title: state.target.title)
            }
        } catch is CancellationError {
            return
        } catch {
            report(error, state: state, previewing: previewing)
        }
    }

    /// Without a panel there is nothing on screen saying the model is working, so the pill says it.
    private func produce(
        _ state: QuickActionPanelState, action: QuickAction, previewing: Bool
    ) async throws -> String {
        guard !previewing else { return try await generate(state, action: action, streaming: true) }
        core.showProgress(state.target.progressTitle)
        defer { core.hideProgress() }
        return try await generate(state, action: action, streaming: false)
    }

    private func generate(
        _ state: QuickActionPanelState, action: QuickAction, streaming: Bool
    ) async throws -> String {
        if action.usesTranslationFramework {
            return try await TextTranslator.translate(state.original, to: state.targetLanguage)
        }
        let provider = try core.quickActionProvider()
        return try await QuickActionRunner.run(
            action, selection: state.original, using: provider,
            instructionOverride: store.settings.instructionOverride(for: action),
            onDelta: { delta in
                guard streaming else { return }
                state.append(delta)
            })
    }

    /// A replacement that never lands would otherwise lose the reply, so the clipboard keeps it.
    private func deliver(_ text: String, to target: NSRunningApplication?, title: String) {
        injector.replaceSelection(
            with: text, in: target,
            onDelivered: { [weak self] in self?.core.showMessage("\(title) applied") },
            onFailed: { [weak self] in
                Paster.copyPlainText(text)
                self?.core.showMessage(
                    "\(title) couldn't replace the selection — copied instead",
                    tone: .danger)
            })
    }

    /// A failure the reader cannot see is a hotkey that silently did nothing.
    private func report(_ error: Error, state: QuickActionPanelState, previewing: Bool) {
        guard previewing else {
            core.showMessage(error.localizedDescription, tone: .danger)
            return
        }
        state.fail(error.localizedDescription)
    }

    private func present(_ state: QuickActionPanelState, target: NSRunningApplication?) {
        panels.present(
            state,
            languages: offeredLanguages,
            onRetranslate: { [weak self] language in
                state.targetLanguage = language
                self?.rerun(state, target: target)
            },
            onDownloaded: { [weak self] in self?.rerun(state, target: target) },
            onReplace: { [weak self] text in
                self?.deliver(text, to: target, title: state.target.title)
            },
            onContinueInChat: { [weak self] in
                guard let self, !state.output.isEmpty else { return }
                self.core.aiChatCoordinator.ask(state.output)
            })
    }

    private func rerun(_ state: QuickActionPanelState, target: NSRunningApplication?) {
        state.restart()
        start { [weak self] in
            guard let self else { return }
            switch state.target {
            case .builtIn:
                await perform(state, target: target, previewing: true)
            case .custom(let customAction):
                await performCustom(state, customAction: customAction, target: target, previewing: true)
            }
        }
    }

    private var targetLanguage: Locale.Language {
        let stored = store.settings.targetLanguage
        guard !stored.isEmpty else { return Locale.current.language }
        return Locale.Language(identifier: stored)
    }

    /// Observed, not ignored: it arrives after the pane has painted, and the picker has to notice.
    private(set) var offeredLanguages: [Locale.Language] = []
    @ObservationIgnored private var languageLoad: Task<Void, Never>?

    func loadLanguages() {
        guard offeredLanguages.isEmpty, languageLoad == nil else { return }
        languageLoad = Task { [weak self] in
            let languages = await TextTranslator.supportedLanguages()
            self?.offeredLanguages = languages
        }
    }
}

extension TextTranslator.Failure {
    var needsDownload: Bool {
        if case .notInstalled = self { return true }
        return false
    }
}
