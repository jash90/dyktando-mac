import AppKit
import AVFAudio
import SwiftUI

struct PrivacyTab: View {
    @StateObject private var permissions = PermissionsService()

    var body: some View {
        Form {
            Section {
                row(title: "Mikrofon",
                    granted: permissions.microphone == .granted,
                    detail: micDetail,
                    action: micAction)

                row(title: "Accessibility (auto-wklejanie)",
                    granted: permissions.accessibility,
                    detail: axDetail,
                    action: axAction)
            } footer: {
                Text("""
                    Bez **Accessibility** Dyktando kopiuje tekst do schowka, \
                    ale nie wciska automatycznie ⌘V — musisz wkleić ręcznie. \
                    Po przyznaniu uprawnienia w Ustawieniach systemowych zwykle \
                    konieczne jest **ponowne uruchomienie aplikacji**, żeby system \
                    zacześł uznawać ją za zaufaną.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Odśwież stan uprawnień") {
                    permissions.refreshAccessibility()
                }
                Button("Zrestartuj Dyktando") {
                    relaunchApp()
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear { permissions.refreshAccessibility() }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(title: String,
                     granted: Bool,
                     detail: String,
                     action: (label: String, run: () -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let action {
                Button(action.label, action: action.run)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Microphone

    private var micDetail: String {
        switch permissions.microphone {
        case .granted:   return "Przyznane. Możesz nagrywać."
        case .denied:    return "Odmówione. Otwórz Ustawienia systemowe."
        case .undetermined: return "Jeszcze nie pytano."
        @unknown default: return "Nieznany stan."
        }
    }

    private var micAction: (String, () -> Void)? {
        switch permissions.microphone {
        case .granted: return nil
        case .denied:
            return ("Otwórz Ustawienia", {
                openSystemSettings("Privacy_Microphone")
            })
        case .undetermined:
            return ("Poproś o dostęp", {
                Task { _ = await permissions.requestMicrophone() }
            })
        @unknown default: return nil
        }
    }

    // MARK: - Accessibility

    private var axDetail: String {
        permissions.accessibility
            ? "Przyznane. Dyktando wkleja tekst automatycznie."
            : "Brak. Tekst trafia tylko do schowka — wciśnij ⌘V ręcznie."
    }

    private var axAction: (String, () -> Void)? {
        if permissions.accessibility { return nil }
        return ("Włącz Accessibility", {
            permissions.promptAccessibility()
            openSystemSettings("Privacy_Accessibility")
        })
    }

    // MARK: - Helpers

    private func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func relaunchApp() {
        guard let bundleURL = Bundle.main.bundleURL as URL? else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
