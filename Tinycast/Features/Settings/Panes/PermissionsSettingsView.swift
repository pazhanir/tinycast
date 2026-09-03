import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var calendarAccess = Permissions.calendarAccess()
    @State private var microphoneAccess = Permissions.microphoneAccess()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Label(
                        accessibilityTrusted ? "Granted" : "Not granted",
                        systemImage: accessibilityTrusted
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
                } label: {
                    SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                    Text("Lets Tinycast paste a clipboard item into the app you were using.")
                }

                LabeledContent {
                    Button(accessibilityTrusted ? "Open…" : "Grant Access…") {
                        Permissions.openAccessibilitySettings()
                    }
                } label: {
                    Text(accessibilityTrusted ? "Manage in System Settings" : "Grant access")
                    Text("Opens Privacy & Security › Accessibility.")
                }
            } header: {
                SettingsSectionHeader(.permissionsAccessibility)
            } footer: {
                Text("Access Tinycast needs to work with other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Label(calendarStatus.title, systemImage: calendarStatus.symbol)
                        .foregroundStyle(calendarStatus.tint)
                } label: {
                    SettingsRowTitle(.permissionsCalendars, "Calendars")
                    Text("Lets Tinycast find the join link for the meeting you are about to be in.")
                }

                LabeledContent {
                    Button("Open…") { Permissions.openCalendarSettings() }
                } label: {
                    Text("Manage in System Settings")
                    Text("Opens Privacy & Security › Calendars.")
                }
            } header: {
                SettingsSectionHeader(.permissionsCalendars)
            }

            Section {
                LabeledContent {
                    Label(microphoneStatus.title, systemImage: microphoneStatus.symbol)
                        .foregroundStyle(microphoneStatus.tint)
                } label: {
                    SettingsRowTitle(.permissionsMicrophone, "Microphone")
                    Text("Lets Tinycast record your voice for speech-to-text dictation.")
                }

                LabeledContent {
                    Button("Open…") { Permissions.openMicrophoneSettings() }
                } label: {
                    Text("Manage in System Settings")
                    Text("Opens Privacy & Security › Microphone.")
                }
            } header: {
                SettingsSectionHeader(.permissionsMicrophone)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.permissions)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private var calendarStatus: (title: String, symbol: String, tint: Color) {
        switch calendarAccess {
        case .granted: return ("Granted", "checkmark.circle.fill", .green)
        case .notDetermined: return ("Not asked yet", "questionmark.circle.fill", .secondary)
        case .denied: return ("Not granted", "exclamationmark.triangle.fill", .orange)
        }
    }

    private var microphoneStatus: (title: String, symbol: String, tint: Color) {
        switch microphoneAccess {
        case .granted: return ("Granted", "checkmark.circle.fill", .green)
        case .notDetermined: return ("Not asked yet", "questionmark.circle.fill", .secondary)
        case .denied: return ("Not granted", "exclamationmark.triangle.fill", .orange)
        }
    }

    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        let access = Permissions.calendarAccess()
        if access != calendarAccess { calendarAccess = access }
        let mic = Permissions.microphoneAccess()
        if mic != microphoneAccess { microphoneAccess = mic }
    }
}
