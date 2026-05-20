import SwiftUI

struct AITab: View {
    @ObservedObject var prefs = Preferences.shared

    @State private var probing = false
    @State private var probeResult: String?
    @State private var probeOK: Bool?

    var body: some View {
        Form {
            Section {
                Toggle("Włącz routing przez Gemmę (Ollama)", isOn: $prefs.aiEnabled)
            } footer: {
                Text("""
                    Gdy włączone: po transkrypcji najpierw sprawdzamy ręczne komendy z zakładki \
                    *Akcje*, a gdy żadna nie pasuje — wysyłamy tekst do lokalnego modelu, który decyduje \
                    czy uruchomić **umiejętność** (np. odtwórz na Spotify, otwórz aplikację), czy zostawić \
                    tekst do wklejenia. Wszystko działa lokalnie, nic nie wychodzi do chmury.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Połączenie z Ollama") {
                HStack {
                    Text("Host").frame(width: 60, alignment: .leading)
                    TextField("http://localhost:11434", text: $prefs.ollamaHost)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                }
                HStack {
                    Text("Model").frame(width: 60, alignment: .leading)
                    TextField("gemma4:latest", text: $prefs.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                    Button(probing ? "Łączę…" : "Sprawdź połączenie") { Task { await probe() } }
                        .disabled(probing)
                }

                if let result = probeResult {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: probeOK == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(probeOK == true ? .green : .red)
                        Text(result)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Dostępne umiejętności") {
                ForEach(SkillRegistry.all, id: \.id) { skill in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.id).font(.system(.body, design: .monospaced))
                        Text(skill.description).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private func probe() async {
        probing = true
        defer { probing = false }
        guard let host = URL(string: prefs.ollamaHost) else {
            probeResult = "Nieprawidłowy URL hosta"
            probeOK = false
            return
        }
        let client = OllamaClient(host: host, model: prefs.ollamaModel)
        do {
            let models = try await client.ping()
            let hasModel = models.contains(prefs.ollamaModel)
            probeOK = hasModel
            if hasModel {
                probeResult = "Połączono. Dostępne modele: \(models.joined(separator: ", "))"
            } else {
                probeResult = "Ollama odpowiada, ale brak modelu '\(prefs.ollamaModel)'. Dostępne: \(models.joined(separator: ", "))"
            }
        } catch {
            probeOK = false
            probeResult = "Błąd: \(error.localizedDescription). Uruchom `ollama serve` lub `brew services start ollama`."
        }
    }
}
