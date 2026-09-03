import SwiftUI

struct DictationSettingsView: View {
    @Environment(DictationSettingsStore.self) private var settings
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        @Bindable var settings = settings

        Form {
            // Master Toggle
            Section {
                Toggle(isOn: $settings.isEnabled) {
                    SettingsRowTitle(.dictation, "Enable Dictation")
                    Text("Dictate speech directly into any active application using Whisper or on-device speech.")
                }
            } header: {
                SettingsSectionHeader(.dictation)
            }

            // Dictate Text Command & Global Hotkey
            Section {
                if let entry = CommandCatalog.entry(for: .dictateText) {
                    SettingsRow(title: entry.name) {
                        Image(systemName: CommandID.dictateText.sfSymbol)
                            .frame(width: Theme.Size.settingsRowIcon)
                    } trailing: {
                        ShortcutRecorder(action: .command(.dictateText))
                        Toggle("", isOn: visibilityBinding(entry))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel("Show \(entry.name) in launcher")
                    }
                }
            } header: {
                Text("Command & Shortcut")
            } footer: {
                Text("Press your global hotkey anywhere to dictate text into the active app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.isEnabled)

            // Provider Section (matches AI Configuration API Compatible style)
            Section {
                editorField("Provider") {
                    Picker("Provider", selection: $settings.provider) {
                        ForEach(DictationProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .labelsHidden()
                }

                if settings.provider == .groq {
                    editorField("Base URL") {
                        TextField(
                            "Base URL",
                            text: $settings.groqBaseURL,
                            prompt: Text("https://api.groq.com/openai/v1")
                        )
                    }

                    editorField("API Key") {
                        HStack(spacing: Theme.Spacing.sm) {
                            SecureField(
                                "API Key",
                                text: $settings.groqApiKey,
                                prompt: Text(settings.groqApiKey.isEmpty ? "Paste API key" : "Leave blank to keep saved key")
                            )

                            Button("Get Key") {
                                if let url = URL(string: "https://console.groq.com/keys") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if !settings.groqApiKey.isEmpty {
                        Label("A key is stored in Keychain", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    editorField("Model ID") {
                        TextField(
                            "Model ID",
                            text: $settings.groqModel,
                            prompt: Text("whisper-large-v3-turbo")
                        )
                    }
                }
            } header: {
                Text("Provider")
            } footer: {
                if settings.provider == .groq {
                    Text("Uses OpenAI-compatible audio transcription endpoints. Custom endpoints and models are supported. API keys stay in your login Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Transcribes audio completely offline using macOS on-device speech recognition. No internet or API key required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsEnabled(settings.isEnabled)

            // Formatting & Context
            Section {
                Picker(selection: $settings.style) {
                    ForEach(DictationStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                } label: {
                    SettingsRowTitle(.dictation, "Transcription Style")
                    Text(settings.style.description)
                }

                Toggle(isOn: $settings.useAppContext) {
                    SettingsRowTitle(.dictation, "Use App Context")
                    Text("Pulls names, places, and terms from your active window to prime Whisper. Stays private in memory.")
                }

                LabeledContent {
                    TextField("E.g. Tinycast, Kubernetes, Pazhani", text: $settings.customVocabulary)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                } label: {
                    SettingsRowTitle(.dictation, "Custom Vocabulary")
                    Text("Comma-separated jargon, project names, or rare words.")
                }
            } header: {
                Text("Formatting & Context")
            }
            .settingsEnabled(settings.isEnabled)

            // Sound & Feedback
            Section {
                Toggle(isOn: $settings.playAudioCues) {
                    SettingsRowTitle(.dictation, "Audio Feedback")
                    Text("Play subtle system sound effects when dictation starts and finishes.")
                }
            } header: {
                Text("Feedback")
            }
            .settingsEnabled(settings.isEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.dictation)
    }

    private func editorField<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        LabeledContent {
            content()
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } label: {
            Text(title).font(.callout.weight(.medium))
        }
    }

    private func visibilityBinding(_ entry: AppEntry) -> Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) }
        )
    }
}
