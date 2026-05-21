import SwiftUI

struct AITab: View {
    @ObservedObject var prefs = Preferences.shared

    @State private var probing = false
    @State private var probeResult: String?
    @State private var probeOK: Bool?

    @State private var discordTesting = false
    @State private var discordResult: String?
    @State private var discordOK: Bool?

    @StateObject private var spotifyAuth = SpotifyOAuth.shared

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

            Section("Discord webhook") {
                HStack {
                    Text("URL").frame(width: 60, alignment: .leading)
                    TextField("https://discord.com/api/webhooks/…", text: $prefs.discordWebhookURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                    Button(discordTesting ? "Wysyłam…" : "Test") { Task { await testDiscord() } }
                        .disabled(discordTesting || prefs.discordWebhookURL.isEmpty)
                }
                if let result = discordResult {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: discordOK == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(discordOK == true ? .green : .red)
                        Text(result).font(.caption).textSelection(.enabled)
                    }
                }
                Text("Stwórz webhook w Discordzie: kanał → Edit → Integrations → Webhooks → New. Skopiuj URL i wklej tutaj. Frazy w stylu \"napisz do Claude X\" / \"powiedz Claudowi X\" trafią jako wiadomość.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Spotify (odtwarzanie albumów głosem)") {
                HStack {
                    Text("Client ID").frame(width: 80, alignment: .leading)
                    TextField("z developer.spotify.com → Create app", text: $prefs.spotifyClientID)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                }
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: spotifyAuth.isAuthenticated
                          ? "checkmark.circle.fill"
                          : "person.crop.circle.badge.questionmark")
                        .foregroundStyle(spotifyAuth.isAuthenticated ? .green : .secondary)
                    VStack(alignment: .leading) {
                        if spotifyAuth.isAuthenticated {
                            Text("Połączono")
                                .font(.body)
                            if let name = spotifyAuth.displayName {
                                Text(name).font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Niepołączono")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if spotifyAuth.isAuthenticated {
                        Button("Rozłącz") { spotifyAuth.logout() }
                    } else {
                        Button("Połącz ze Spotify") {
                            spotifyAuth.startLogin(clientID: prefs.spotifyClientID)
                        }
                        .disabled(prefs.spotifyClientID.isEmpty)
                    }
                }
                if let err = spotifyAuth.lastError {
                    Text(err).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                Text("Setup: developer.spotify.com/dashboard → Create app → Redirect URI: `dyktando://spotify-callback`, zaznacz Web API. Skopiuj Client ID i wklej powyżej. Odtwarzanie wymaga konta Premium.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func testDiscord() async {
        discordTesting = true
        defer { discordTesting = false }
        guard let url = URL(string: prefs.discordWebhookURL) else {
            discordOK = false
            discordResult = "Nieprawidłowy URL"
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "content": "🤖 Test z Dyktando — webhook działa.",
            "username": "Dyktando",
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                discordOK = true
                discordResult = "Wysłano. Sprawdź kanał."
            } else {
                discordOK = false
                let body = String(data: data, encoding: .utf8) ?? "?"
                discordResult = "HTTP error: \(body)"
            }
        } catch {
            discordOK = false
            discordResult = "Błąd: \(error.localizedDescription)"
        }
    }
}
