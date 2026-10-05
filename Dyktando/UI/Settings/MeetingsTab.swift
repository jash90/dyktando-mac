import SwiftUI

/// Ustawienia → Spotkania.
struct MeetingsTab: View {
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Transkrypcja") {
                Picker("Model do spotkań", selection: $prefs.meetingEngineID) {
                    ForEach(EngineID.allCases, id: \.self) { id in
                        Text(EngineRegistry.shared.engine(for: id)?.displayName ?? id.rawValue).tag(id.rawValue)
                    }
                }
                Toggle("Rozpoznawaj poszczególnych rozmówców (Rozmówca 1, 2…)", isOn: $prefs.meetingDiarization)
                Toggle("Przepisz automatycznie po zakończeniu nagrywania", isOn: $prefs.meetingAutoTranscribe)
                Toggle("Podsumuj automatycznie po transkrypcji (wysyła transkrypt do dostawcy AI)", isOn: $prefs.meetingAutoSummarize)
                Text("Najlepsze wyniki w słuchawkach — inaczej głos rozmówców z głośników trafia też do mikrofonu (Dyktando odrzuca takie echo, ale nie zawsze idealnie).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Nagrywanie") {
                Toggle("Podpowiadaj nagranie, gdy aplikacja do rozmów zacznie używać mikrofonu", isOn: $prefs.meetingDetectionPrompt)
                Stepper(value: $prefs.meetingAudioRetentionDays, in: 0...365, step: 1) {
                    Text(prefs.meetingAudioRetentionDays == 0
                         ? "Audio spotkań: trzymaj zawsze"
                         : "Usuwaj audio po \(prefs.meetingAudioRetentionDays) dniach (transkrypt i podsumowania zostają)")
                }
                Text("Pamiętaj, by poinformować rozmówców o nagrywaniu. Dźwięk z aplikacji wymaga zgody „Nagrywanie dźwięku systemowego” (macOS 14.4+).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Otwórz listę spotkań…") { MeetingsWindowController.shared.show() }
                Button("Pokaż folder spotkań w Finderze") {
                    try? FileManager.default.createDirectory(at: MeetingStore.shared.root, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([MeetingStore.shared.root])
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
