import SwiftUI

/// Ustawienia → AI: dostawcy do podsumowań spotkań. Klucze idą wyłącznie do pęku kluczy.
struct AITab: View {
    @AppStorage(AISettings.defaultProviderKey) private var defaultProvider = AIProviderID.anthropic.rawValue
    @AppStorage(AISettings.promptKey) private var prompt = ""
    @State private var selected: AIProviderID = .anthropic

    var body: some View {
        Form {
            Section {
                Picker("Domyślny dostawca", selection: $defaultProvider) {
                    ForEach(AIProviderID.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                Text("Do podsumowania wysyłany jest tylko tekst transkryptu — nagranie i sama transkrypcja zostają na Twoim Macu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Konfiguracja dostawcy") {
                Picker("Dostawca", selection: $selected) {
                    ForEach(AIProviderID.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                ProviderSettings(provider: selected).id(selected)
            }
            Section {
                TextEditor(text: Binding(get: { prompt.isEmpty ? MeetingSummarizer.defaultPrompt : prompt },
                                         set: { prompt = $0 == MeetingSummarizer.defaultPrompt ? "" : $0 }))
                    .font(.callout)  // czcionka mono w małym rozmiarze gubiła kreski nad ś/ó/ń
                    .frame(minHeight: 160)
                Button("Przywróć domyślny prompt") { prompt = "" }
            } header: {
                Text("Prompt podsumowania")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}

private struct ProviderSettings: View {
    let provider: AIProviderID
    @State private var keyInput = ""
    @State private var hasKey = false
    @State private var model = ""
    @State private var baseURL = ""
    @State private var models: [String] = []
    @State private var customModel = false
    @State private var loadingModels = false
    private static let customTag = "__custom__"
    @State private var status: String?
    @State private var testing = false

    var body: some View {
        Group {
            HStack {
                SecureField("Klucz API", text: $keyInput,
                            prompt: Text(hasKey ? "zapisany ✓ — wklej nowy, aby zmienić" : "wklej klucz API"))
                    .onSubmit(saveKey)
                Button("Zapisz") { saveKey() }.disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if hasKey {
                    Button("Usuń", role: .destructive) {
                        KeychainStore.ai.delete(provider.rawValue)
                        hasKey = false
                    }
                }
            }
            modelPicker
            TextField("Adres API", text: $baseURL, prompt: Text(provider.defaultBaseURL))
                .onSubmit(saveBaseURL)
            HStack {
                Button(testing ? "Sprawdzam…" : "Testuj połączenie") { Task { await test() } }
                    .disabled(testing || !hasKey)
                if let status { Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            }
        }
        .onAppear(perform: load)
        .onDisappear { saveModel(); saveBaseURL() }
    }

    @ViewBuilder private var modelPicker: some View {
        if models.isEmpty || customModel {
            HStack {
                TextField("Model", text: $model, prompt: Text(provider.modelPlaceholder))
                    .onSubmit(saveModel)
                if loadingModels {
                    ProgressView().controlSize(.small)
                } else if !models.isEmpty {
                    Button("Lista") { customModel = false }
                } else if hasKey {
                    Button("Pobierz listę modeli") { Task { await fetchModels() } }
                }
            }
        } else {
            HStack {
                Picker("Model", selection: Binding(
                    get: { model.isEmpty ? "" : model },
                    set: { value in
                        if value == Self.customTag {
                            customModel = true
                        } else {
                            model = value
                            saveModel()
                        }
                    })) {
                    if model.isEmpty { Text("— wybierz model —").tag("") }
                    ForEach(pickerModels, id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text("Inny… (wpisz nazwę)").tag(Self.customTag)
                }
                Button {
                    Task { await fetchModels() }
                } label: {
                    if loadingModels { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.borderless)
                .help("Odśwież listę modeli")
                .disabled(loadingModels)
            }
        }
    }

    /// Lista z dostawcy + bieżący model, gdyby go na niej nie było (np. wpisany ręcznie).
    private var pickerModels: [String] {
        model.isEmpty || models.contains(model) ? models : [model] + models
    }

    private var modelsCacheKey: String { "ai.\(provider.rawValue).modelsCache" }

    private func fetchModels() async {
        guard let key = KeychainStore.ai.get(provider.rawValue) else { return }
        saveBaseURL()
        loadingModels = true
        defer { loadingModels = false }
        let config = LLMConfig(provider: provider, apiKey: key, model: model, baseURL: AISettings.baseURL(provider))
        do {
            let fetched = try await config.makeProvider().listModels()
            models = fetched
            UserDefaults.standard.set(fetched, forKey: modelsCacheKey)
            customModel = false
            status = "Pobrano \(fetched.count) modeli."
        } catch {
            status = "Nie udało się pobrać listy modeli: \(error.localizedDescription)"
        }
    }

    private func load() {
        hasKey = KeychainStore.ai.has(provider.rawValue)
        model = UserDefaults.standard.string(forKey: AISettings.modelKey(provider)) ?? provider.defaultModel
        baseURL = UserDefaults.standard.string(forKey: AISettings.baseURLKey(provider)) ?? ""
        models = UserDefaults.standard.stringArray(forKey: modelsCacheKey) ?? []
        if hasKey && models.isEmpty { Task { await fetchModels() } }
    }

    private func saveKey() {
        do {
            try KeychainStore.ai.set(keyInput.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.rawValue)
            keyInput = ""
            hasKey = true
            status = "Klucz zapisany."
            Task { await fetchModels() }  // od razu sprawdza klucz i wypełnia listę modeli
        } catch {
            status = "Nie udało się zapisać klucza: \(error.localizedDescription)"
        }
    }

    private func saveModel() {
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespaces), forKey: AISettings.modelKey(provider))
    }

    private func saveBaseURL() {
        UserDefaults.standard.set(baseURL.trimmingCharacters(in: .whitespaces), forKey: AISettings.baseURLKey(provider))
    }

    /// Lista modeli (GET /models) potwierdza klucz i adres bez płatnego zapytania.
    private func test() async {
        saveModel(); saveBaseURL()
        testing = true
        defer { testing = false }
        guard let key = KeychainStore.ai.get(provider.rawValue) else { status = "Brak klucza."; return }
        let config = LLMConfig(provider: provider, apiKey: key, model: AISettings.model(provider), baseURL: AISettings.baseURL(provider))
        do {
            models = try await config.makeProvider().listModels()
            UserDefaults.standard.set(models, forKey: modelsCacheKey)
            let current = AISettings.model(provider)
            if current.isEmpty {
                status = "Połączenie działa — \(models.count) modeli. Wybierz model z listy."
            } else if models.isEmpty || models.contains(current) {
                status = "Połączenie działa, model „\(current)” dostępny."
            } else {
                status = "Połączenie działa, ale modelu „\(current)” nie ma na liście (\(models.count) dostępnych)."
            }
        } catch {
            status = error.localizedDescription
        }
    }
}
