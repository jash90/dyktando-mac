import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                Toggle("Pokaż pływający HUD", isOn: hudEnabledBinding)
                Toggle("Uruchamiaj przy starcie systemu", isOn: launchAtLoginBinding)
            } footer: {
                Text("HUD to pływająca pigułka pokazująca stan dyktowania. Przeciągnij ją w wybrane miejsce — pozycja zapamiętuje się między uruchomieniami.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var hudEnabledBinding: Binding<Bool> {
        Binding(
            get: { prefs.hudEnabled },
            set: { newValue in
                prefs.hudEnabled = newValue
                AppDelegate.shared?.setHUDVisible(newValue)
            }
        )
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
                    print("Failed to update launch-at-login: \(error)")
                    prefs.launchAtLogin = !newValue
                }
            }
        )
    }
}
