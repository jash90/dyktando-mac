import SwiftUI

struct AudioTab: View {
    @AppStorage(AudioDevices.preferenceKey) private var selectedUID: String = ""
    @State private var devices: [AudioInputDevice] = AudioDevices.inputDevices()
    @State private var systemDefault: AudioInputDevice? = AudioDevices.defaultInputDevice()

    var body: some View {
        Form {
            Section {
                Picker("Urządzenie", selection: $selectedUID) {
                    Text("Domyślne systemowe (\(systemDefault?.name ?? "brak"))").tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                    // Zapisane urządzenie, które jest teraz odłączone — zostaw je na liście.
                    if !selectedUID.isEmpty, !devices.contains(where: { $0.uid == selectedUID }) {
                        Text("Odłączone urządzenie (używam domyślnego)").tag(selectedUID)
                    }
                }
                Button("Odśwież listę") { refresh() }
            } header: {
                Text("Wejście")
            } footer: {
                Text("Wybrane urządzenie działa od następnego nagrania. Gdy jest odłączone, Dyktando nagrywa z domyślnego wejścia systemu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Próbkowanie", value: "16 kHz mono Float32 (stałe)")
            } header: {
                Text("Format")
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        devices = AudioDevices.inputDevices()
        systemDefault = AudioDevices.defaultInputDevice()
    }
}
