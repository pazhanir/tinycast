import Combine
import SwiftUI

/// A peer of the AI pane, not a section in it: it only borrows the provider layer.
struct QuickActionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var appSettings
    @Environment(QuickActionSettingsStore.self) private var store
    @Environment(AISettingsStore.self) private var aiSettings
    @Environment(VisibilityStore.self) private var visibility

    /// Polled like the Permissions pane: the grant lands in System Settings, which sends nothing.
    @State private var isTrusted = Permissions.isAccessibilityTrusted()
    @State private var editingAction: QuickAction?
    @State private var editingCustomAction: CustomQuickAction?
    @State private var isCreatingCustomAction = false
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsRowTitle(.quickActionsQuickActions, "Enable Quick Actions")
                    Text(
                        "Act on the text you have selected in any app. Nothing is read until you "
                            + "press a shortcut.")
                }
                if appSettings.quickActionsEnabled, !isTrusted {
                    // Every shortcut fails without it; better said here than found one press later.
                    SettingsRow(
                        title: "Accessibility permission required",
                        subtitle: "Tinycast can't read your selection until it is granted."
                    ) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.destructive)
                            .frame(width: Theme.Size.settingsRowIcon)
                    } trailing: {
                        Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                    }
                }
            } header: {
                SettingsSectionHeader(.quickActionsQuickActions)
            }

            Group {
                actionsSection
                customActionsSection
                modelSection
                languageSection
            }
            .settingsEnabled(appSettings.quickActionsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.quickActions)
        .onReceive(refreshTimer) { _ in isTrusted = Permissions.isAccessibilityTrusted() }
        .sheet(item: $editingAction) { action in
            InstructionsEditorSheet(
                action: action,
                instructionOverride: store.settings.instructionOverride(for: action)
            ) { instructionOverride in
                store.settings.setInstructionOverride(instructionOverride, for: action)
            }
        }
        .sheet(item: $editingCustomAction) { action in
            CustomQuickActionEditorSheet(action: action, modelChoices: modelChoices) { updated in
                store.updateCustomAction(updated)
            }
        }
        .sheet(isPresented: $isCreatingCustomAction) {
            CustomQuickActionEditorSheet(action: nil, modelChoices: modelChoices) { created in
                store.addCustomAction(created)
            }
        }
        .onAppear {
            core.quickActionCoordinator.loadLanguages()
            store.resolveModel(
                appleIntelligenceAvailable: aiSettings.isAppleIntelligenceAvailable(),
                fallback: aiSettings.defaultModel)
            core.applyInstalledAILifecycle()
        }
        .onChange(of: appSettings.aiEnabled) { repairInstalledModel() }
        .onChange(of: aiSettings.enabledInstalledProviders) {
            core.applyInstalledAILifecycle()
            repairInstalledModel()
        }
        .onChange(of: core.chatGPTSubscription.models) { repairInstalledModel() }
        .onChange(of: core.chatGPTSubscription.phase) { repairInstalledModel() }
        .onChange(of: core.installedAI.statuses) { repairInstalledModel() }
    }

    private var actionsSection: some View {
        Section {
            ForEach(QuickAction.allCases) { action in
                SettingsRow(title: action.title, subtitle: subtitle(for: action)) {
                    Image(systemName: action.symbol)
                        .frame(width: Theme.Size.settingsRowIcon)
                } trailing: {
                    if !action.usesTranslationFramework {
                        Button {
                            editingAction = action
                        } label: {
                            SymbolImage(
                                name: "pencil", size: Theme.Size.quickActionHeaderIcon)
                        }
                        .buttonStyle(.plain)
                        .help("Edit \(action.title) instructions")
                        .accessibilityLabel("Edit \(action.title) instructions")
                    }
                    ShortcutRecorder(action: .command(CommandID(action)), isQuiet: true)
                    Picker("", selection: previewBinding(action)) {
                        Text("Replace").tag(false)
                        Text("Preview").tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(action.alwaysPreviews)
                    .accessibilityLabel("What \(action.title) does with its result")
                    if let entry = CommandCatalog.entry(for: CommandID(action)) {
                        Toggle("", isOn: launcherBinding(entry))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel("Show \(action.title) in launcher")
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.quickActionsActions)
        } footer: {
            Text(
                "Replace puts the result straight into your document — undo in the app you were in "
                    + "brings it back. Preview shows it in a panel first. The checkbox lists the "
                    + "action in the launcher; its shortcut works either way."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var customActionsSection: some View {
        Section {
            if store.customActions.isEmpty {
                Text("No custom quick actions yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.customActions) { action in
                    SettingsRow(
                        title: action.name,
                        subtitle: action.descriptionText.isEmpty ? (action.prompt.components(separatedBy: .newlines).first ?? "") : action.descriptionText
                    ) {
                        Image(systemName: action.symbol)
                            .frame(width: Theme.Size.settingsRowIcon)
                    } trailing: {
                        Button {
                            editingCustomAction = action
                        } label: {
                            SymbolImage(name: "pencil", size: Theme.Size.quickActionHeaderIcon)
                        }
                        .buttonStyle(.plain)
                        .help("Edit \(action.name)")

                        ShortcutRecorder(action: .quickAction(id: action.id), isQuiet: true)

                        Button(role: .destructive) {
                            store.removeCustomAction(id: action.id)
                        } label: {
                            SymbolImage(name: "trash", size: Theme.Size.quickActionHeaderIcon)
                        }
                        .buttonStyle(.plain)
                        .help("Delete \(action.name)")

                        Toggle("", isOn: Binding(
                            get: { action.isEnabled },
                            set: { enabled in
                                var updated = action
                                updated.isEnabled = enabled
                                store.updateCustomAction(updated)
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .help(action.isEnabled ? "Enabled" : "Disabled")
                    }
                }
            }

            LabeledContent {
                Button("Create Quick Action…") {
                    isCreatingCustomAction = true
                }
            } label: {
                SettingsRowTitle(.quickActionsActions, "New Custom Action")
                Text("Create an AI command powered by dynamic placeholders and output routing.")
            }
        } header: {
            HStack {
                Text("Custom Quick Actions (AI Commands)")
                Spacer()
                Button {
                    isCreatingCustomAction = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        } footer: {
            Text("Create custom AI commands with Raycast Dynamic Placeholders like {selection}, {clipboard}, {argument name=\"…\"}, {date}, and {calculator …}. Output directly to panel, AI Chat, or document.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelSection: some View {
        Section {
            AIModelSelectionRows(
                selection: store.model,
                select: store.select,
                modelLabel: {
                    SettingsRowTitle(.quickActionsModel, "Model")
                    Text("Used by every action except Translate.")
                },
                effortLabel: {
                    SettingsRowTitle(.quickActionsModel, "Reasoning effort")
                    Text("Applied when the selected model supports reasoning effort.")
                }
            )
        } header: {
            SettingsSectionHeader(.quickActionsModel)
        } footer: {
            Text(
                "Separate from chat's model on purpose: a shortcut you press all day should not "
                    + "bill an API every time. Apple Intelligence runs on this Mac for nothing."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: languageBinding) {
                Text("Same as this Mac").tag("")
                ForEach(core.quickActionCoordinator.offeredLanguages, id: \.minimalIdentifier) {
                    Text(TextTranslator.displayName(of: $0)).tag($0.minimalIdentifier)
                }
            } label: {
                SettingsRowTitle(.quickActionsTranslate, "Translate to")
                Text("The panel can still translate into another language once it is open.")
            }
        } header: {
            SettingsSectionHeader(.quickActionsTranslate)
        } footer: {
            Text(
                "Translation uses Apple's own translator on this Mac, so it costs nothing and "
                    + "reaches no provider. A language downloads the first time you use it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func subtitle(for action: QuickAction) -> String? {
        action.alwaysPreviews ? "Always shown in a panel" : nil
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { appSettings.quickActionsEnabled },
            set: { core.quickActionCoordinator.setEnabled($0) })
    }

    private func previewBinding(_ action: QuickAction) -> Binding<Bool> {
        Binding(
            get: { store.settings.previewsResult(action) },
            set: { store.settings.setPreviewsResult($0, for: action) })
    }

    private func launcherBinding(_ entry: AppEntry) -> Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) })
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { store.settings.targetLanguage },
            set: { store.settings.targetLanguage = $0 })
    }

    private var modelChoices: [AIModelOption] {
        AIModelOption.availableGroups(
            settings: aiSettings, subscription: core.chatGPTSubscription,
            installedAI: core.installedAI
        )
        .flatMap(\.options)
    }

    private func repairInstalledModel() {
        // Catalog rows name a route without an effort; a repaired selection must carry the default.
        let options = modelChoices.map {
            AIModelOption.withDefaultEffort(
                $0.selection, settings: aiSettings, subscription: core.chatGPTSubscription,
                installedAI: core.installedAI)
        }
        var unavailable = Set<AIModelSource>()
        if !aiSettings.enabledInstalledProviders.contains(.codex)
            || core.chatGPTSubscription.phase == .signedOut
            || core.chatGPTSubscription.phase.isUnavailable
        {
            unavailable.insert(.codex)
        }
        for kind in [InstalledAIKind.claude, .openCode] {
            let phase = core.installedAI.status(for: kind).phase
            guard
                !aiSettings.enabledInstalledProviders.contains(kind)
                    || phase == .signInRequired || phase == .notInstalled
            else { continue }
            unavailable.insert(kind.source)
        }
        store.repairInstalledModel(
            available: options, unavailableSources: unavailable,
            fallback: aiSettings.defaultModel)
    }

    private struct InstructionsEditorSheet: View {
        @Environment(\.dismiss) private var dismiss
        @State private var instructions: String

        let action: QuickAction
        let builtIn: String
        let onSave: (String?) -> Void

        init(
            action: QuickAction, instructionOverride: String?,
            onSave: @escaping (String?) -> Void
        ) {
            self.action = action
            let builtIn = QuickActionPrompt.instructions(for: action)
            _instructions = State(initialValue: instructionOverride ?? builtIn)
            self.builtIn = builtIn
            self.onSave = onSave
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("Customize \(action.title)")
                    .font(.title2.weight(.bold))

                Text("Tell Tinycast how you want \(action.title) to handle your selected text.")
                    .foregroundStyle(.secondary)

                TextEditor(text: $instructions)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.sm)
                    .frame(height: Theme.Size.editorTextHeight * 2)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )

                HStack {
                    Button("Use Default") { instructions = builtIn }
                        .disabled(instructions == builtIn)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        onSave(instructions == builtIn ? nil : instructions)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Theme.Spacing.xxl)
            .frame(width: Theme.Size.editorSheetWidth)
        }
    }

    private struct CustomQuickActionEditorSheet: View {
        @Environment(\.dismiss) private var dismiss
        @State private var name: String
        @State private var descriptionText: String
        @State private var prompt: String
        @State private var symbol: String
        @State private var showingIconPicker = false
        @State private var outputMode: CustomQuickAction.OutputMode
        @State private var selectedModel: AIModelSelection?

        private static let iconSymbols = [
            "wand.and.sparkles", "sparkles", "brain", "text.bubble", "bubble.left.and.bubble.right",
            "character.book.closed", "doc.text", "quote.bubble", "text.quote", "text.alignleft",
            "list.bullet", "checkmark.circle", "arrow.triangle.2.circlepath", "magnifyingglass", "bolt",
            "pencil", "highlighter", "scissors", "clipboard", "doc.on.clipboard",
            "link", "globe", "safari", "terminal", "command",
            "gear", "cpu", "network", "lock", "key",
            "bell", "flag", "star", "bookmark", "tray",
            "paperplane", "cart", "gift", "heart", "folder",
            "waveform", "mic", "photo", "camera", "chart.bar",
            "tablecells", "arrow.up.right", "clock", "person", "creditcard"
        ]

        let originalAction: CustomQuickAction?
        let modelChoices: [AIModelOption]
        let onSave: (CustomQuickAction) -> Void

        init(action: CustomQuickAction?, modelChoices: [AIModelOption], onSave: @escaping (CustomQuickAction) -> Void) {
            self.originalAction = action
            self.modelChoices = modelChoices
            _name = State(initialValue: action?.name ?? "")
            _descriptionText = State(initialValue: action?.descriptionText ?? "")
            _prompt = State(initialValue: action?.prompt ?? "")
            _symbol = State(initialValue: action?.symbol ?? "wand.and.sparkles")
            _outputMode = State(initialValue: action?.outputMode ?? .previewInPanel)
            _selectedModel = State(initialValue: action?.model)
            self.onSave = onSave
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(originalAction == nil ? "New Quick Action" : "Edit Quick Action")
                    .font(.title2.weight(.bold))

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Name").font(.subheadline.weight(.medium))
                    TextField("e.g. Explain Code", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Description (Optional)").font(.subheadline.weight(.medium))
                    TextField("e.g. Explains code and suggests improvements", text: $descriptionText)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Icon").font(.subheadline.weight(.medium))
                        Button {
                            showingIconPicker = true
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: symbol.isEmpty ? "wand.and.sparkles" : symbol)
                                    .frame(width: 16, height: 16)
                                Text(symbol.isEmpty ? "wand.and.sparkles" : symbol)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                    .fill(Theme.Colors.cardFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                    .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                            SymbolPicker(
                                selection: Binding(
                                    get: { symbol.isEmpty ? nil : symbol },
                                    set: { symbol = $0 ?? "wand.and.sparkles" }
                                ),
                                fallback: "wand.and.sparkles",
                                symbols: Self.iconSymbols
                            ) {
                                showingIconPicker = false
                            }
                            .padding(Theme.Spacing.md)
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Output Mode").font(.subheadline.weight(.medium))
                        Picker("", selection: $outputMode) {
                            ForEach(CustomQuickAction.OutputMode.allCases, id: \.self) { mode in
                                Label(mode.title, systemImage: mode.symbol).tag(mode)
                            }
                        }
                        .labelsHidden()
                    }
                }

                if outputMode == .openInAIChat {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundStyle(.secondary)
                        Text("Sends prompt to AI Chat using your active conversation and model settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Model Override (Optional)").font(.subheadline.weight(.medium))
                        Picker("", selection: $selectedModel) {
                            Text("Default Quick Action Model").tag(Optional<AIModelSelection>.none)
                            ForEach(modelChoices, id: \.selection) { option in
                                Text(option.title).tag(Optional(option.selection))
                            }
                        }
                        .labelsHidden()
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Prompt Template").font(.subheadline.weight(.medium))
                    Text("Use dynamic placeholders to insert context into the prompt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Helper chips to insert placeholders
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            insertChip("{selection}", label: "Selection")
                            insertChip("{clipboard}", label: "Clipboard")
                            insertChip("{argument name=\"Topic\"}", label: "Argument")
                            insertChip("{date}", label: "Date")
                            insertChip("{time}", label: "Time")
                            insertChip("{calculator expression=\"2 + 2\"}", label: "Calculator")
                            insertChip("{uuid}", label: "UUID")
                        }
                    }

                    TextEditor(text: $prompt)
                        .font(.body.monospaced())
                        .scrollContentBackground(.hidden)
                        .padding(Theme.Spacing.sm)
                        .frame(height: Theme.Size.editorTextHeight * 2)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                .fill(Theme.Colors.cardFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                        )
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        let action = CustomQuickAction(
                            id: originalAction?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Action" : name,
                            descriptionText: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                            prompt: prompt,
                            symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "wand.and.sparkles" : symbol,
                            outputMode: outputMode,
                            model: (outputMode == .openInAIChat) ? nil : selectedModel,
                            isEnabled: originalAction?.isEnabled ?? true
                        )
                        onSave(action)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompt.isEmpty)
                }
            }
            .padding(Theme.Spacing.xxl)
            .frame(width: Theme.Size.editorSheetWidth + 60)
        }

        private func insertChip(_ token: String, label: String) -> some View {
            Button {
                prompt.append(token)
            } label: {
                Text(label)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.Colors.cardFill)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}
