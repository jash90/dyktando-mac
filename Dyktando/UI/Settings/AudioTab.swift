import SwiftUI
import AVFoundation

struct AudioTab: View {
    @State private var devices: [String] = AudioTab.discoverInputDevices()
    @State private var selected: String = AudioTab.currentInputName()

    var body: some View {
        Form {
            Section {
                Picker("Urządzenie", selection: $selected) {
                    ForEach(devices, id: \.self) { Text($0).tag($0) }
                }
            } header: {
                Text("Wejście")
            } footer: {
                Text("Wybór jest informacyjny w tej wersji — system używa domyślnego wejścia. Pełna integracja w kolejnej wersji.")
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
    }

    static func discoverInputDevices() -> [String] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices.map { $0.localizedName }
    }

    static func currentInputName() -> String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "Domyślne"
    }
}
