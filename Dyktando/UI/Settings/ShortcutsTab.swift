import SwiftUI
import KeyboardShortcuts

struct ShortcutsTab: View {
    var body: some View {
        Form {
            Section("Skróty") {
                KeyboardShortcuts.Recorder("Push-to-talk", name: .pushToTalk)
                KeyboardShortcuts.Recorder("Przełącz dyktowanie", name: .toggleDictation)
                KeyboardShortcuts.Recorder("Otwórz Ustawienia", name: .openSettings)
            }
            Section {
                Button("Przywróć domyślne") {
                    KeyboardShortcuts.reset(.pushToTalk, .toggleDictation, .openSettings)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
