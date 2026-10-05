import SwiftUI
import KeyboardShortcuts

struct ShortcutsTab: View {
    @AppStorage(ModifierKey.defaultsKey) private var modifierPTT: String = ""

    var body: some View {
        Form {
            Section("Skróty") {
                KeyboardShortcuts.Recorder("Push-to-talk", name: .pushToTalk)
                KeyboardShortcuts.Recorder("Przełącz dyktowanie", name: .toggleDictation)
                KeyboardShortcuts.Recorder("Otwórz Ustawienia", name: .openSettings)
                KeyboardShortcuts.Recorder("Nagrywanie spotkania (start/stop)", name: .toggleMeetingRecording)
            }
            Section {
                Picker("Push-to-talk klawiszem modyfikującym", selection: $modifierPTT) {
                    Text("Wyłączone").tag("")
                    ForEach(ModifierKey.allCases) { key in
                        Text(key.title).tag(key.rawValue)
                    }
                }
                Text("Przytrzymaj wybrany klawisz, mów, puść. Działa razem ze skrótem powyżej. "
                     + "Gdy w trakcie wciśniesz inny klawisz (np. ⌘C), nagranie jest odrzucane. "
                     + "Wymaga uprawnienia Dostępności.")
                    .font(.caption).foregroundStyle(.secondary)
                if modifierPTT == ModifierKey.function.rawValue {
                    Text("Dla fn/🌐 ustaw w Ustawieniach systemowych → Klawiatura „Naciśnij 🌐, aby…” na „Nic nie rób”, "
                         + "inaczej macOS otworzy emoji albo własne dyktowanie.")
                        .font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Sam modyfikator (np. prawy ⌘)")
            }
            Section {
                Button("Przywróć domyślne") {
                    KeyboardShortcuts.reset(.pushToTalk, .toggleDictation, .openSettings, .toggleMeetingRecording)
                    modifierPTT = ""
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
