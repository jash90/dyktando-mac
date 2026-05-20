import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                Toggle("Pokaż HUD przy kursorze", isOn: $prefs.hudEnabled)
                Toggle("Uruchamiaj przy starcie systemu", isOn: launchAtLoginBinding)
            } footer: {
                Text("HUD pokazuje stan dyktowania (nasłuchuję / transkrybuję / wynik) tuż obok kursora.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { prefs.launchAtLogin },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    prefs.launchAtLogin = newValue
                } catch {
                    // Revert on failure; surface error in console for now.
                    print("Failed to update launch-at-login: \(error)")
                    prefs.launchAtLogin = !newValue
                }
            }
        )
    }
}
