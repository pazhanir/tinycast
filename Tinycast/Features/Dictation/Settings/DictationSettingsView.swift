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

            // Transcription Provider
            Section {
                Picker(selection: $settings.provider) {
                    ForEach(DictationProvider.allCases) { provider in
                        VStack(alignment: .leading) {
                            Text(provider.title)
                        }
                        .tag(provider)
                    }
                } label: {
                    SettingsRowTitle(.dictation, "Transcription Engine")
                    Text(settings.provider.subtitle)
                }

                if settings.provider == .groq {
                    LabeledContent {
                        HStack(spacing: 8) {
                            SecureField("gsk_...", text: $settings.groqApiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 240)

                            Button("Get Key") {
                                if let url = URL(string: "https://console.groq.com/keys") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    } label: {
                        SettingsRowTitle(.dictation, "Groq API Key")
                        Text("Free tier includes up to 2 hours of audio per day.")
                    }

                    LabeledContent {
                        TextField("whisper-large-v3-turbo", text: $settings.groqModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                    } label: {
                        SettingsRowTitle(.dictation, "Model")
                        Text("Defaults to whisper-large-v3-turbo.")
                    }
                }
            } header: {
                Text("Engine & Provider")
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

    private func visibilityBinding(_ entry: AppEntry) -> Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) }
        )
    }
}
