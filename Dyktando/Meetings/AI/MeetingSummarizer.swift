import Foundation

/// Ustawienia AI: model i adres API w UserDefaults, klucz w pęku kluczy.
enum AISettings {
    static let defaultProviderKey = "ai.defaultProvider"
    static let promptKey = "ai.summaryPrompt"

    static func modelKey(_ p: AIProviderID) -> String { "ai.\(p.rawValue).model" }
    static func baseURLKey(_ p: AIProviderID) -> String { "ai.\(p.rawValue).baseURL" }

    static var defaultProvider: AIProviderID {
        get { UserDefaults.standard.string(forKey: defaultProviderKey).flatMap(AIProviderID.init) ?? .anthropic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultProviderKey) }
    }

    static func model(_ p: AIProviderID) -> String {
        let saved = UserDefaults.standard.string(forKey: modelKey(p)) ?? ""
        return saved.isEmpty ? p.defaultModel : saved
    }

    static func baseURL(_ p: AIProviderID) -> String {
        let saved = UserDefaults.standard.string(forKey: baseURLKey(p)) ?? ""
        return saved.isEmpty ? p.defaultBaseURL : saved
    }

    static var prompt: String {
        let saved = UserDefaults.standard.string(forKey: promptKey) ?? ""
        return saved.isEmpty ? MeetingSummarizer.defaultPrompt : saved
    }

    /// Pełna konfiguracja albo czytelny błąd, czego brakuje.
    static func config(for p: AIProviderID, keychain: KeychainStore = .ai) throws -> LLMConfig {
        guard let key = keychain.get(p.rawValue), !key.isEmpty else {
            throw LLMError(message: "Brak klucza API dla \(p.displayName) — dodaj go w Ustawieniach → AI.")
        }
        let model = model(p)
        guard !model.isEmpty else {
            throw LLMError(message: "Wybierz model dla \(p.displayName) w Ustawieniach → AI.")
        }
        return LLMConfig(provider: p, apiKey: key, model: model, baseURL: baseURL(p))
    }
}

/// Podsumowanie transkryptu przez wybranego dostawcę. Krótki transkrypt → jedno zapytanie;
/// dłuższy niż mieści model → notatki z kolejnych części (ze znacznikami czasu) i ich złożenie.
struct MeetingSummarizer {
    static let defaultPrompt = """
    Jesteś asystentem, który przygotowuje notatki ze spotkań. Na podstawie transkryptu przygotuj \
    podsumowanie po polsku w Markdown z sekcjami:

    ## Streszczenie
    3–6 zdań: o czym było spotkanie i z jakim wynikiem.

    ## Decyzje
    Lista podjętych decyzji (kto zdecydował, jeśli wiadomo).

    ## Zadania
    Lista w formie „- [ ] Kto — co — termin”. Brak osoby lub terminu oznacz jako „nie ustalono”.

    ## Otwarte pytania
    Sprawy bez odpowiedzi lub do wyjaśnienia.

    ## Ryzyka
    Problemy, zagrożenia i zależności, o których mówiono.

    Zasady: opieraj się wyłącznie na transkrypcie, niczego nie dopowiadaj. Mówców nazywaj tak jak \
    w transkrypcie („Ja”, „Rozmówca 1”…), chyba że z rozmowy wynika ich imię. Przy kluczowych \
    ustaleniach podawaj znacznik czasu z transkryptu, np. [00:12:34]. Pustą sekcję oznacz „brak”. \
    Transkrypt pochodzi z automatycznego rozpoznawania mowy i może zawierać błędy — popraw oczywiste \
    przekręcenia słów, ale nie zmieniaj sensu.
    """

    static let partialInstruction = """
    To jest część %d z %d długiego transkryptu. Zrób szczegółowe notatki tej części (decyzje, zadania \
    z osobami i terminami, otwarte pytania, ryzyka, ważne liczby) ze znacznikami czasu. To nie jest \
    jeszcze końcowe podsumowanie — nic nie pomijaj.
    """

    static let finalInstruction = """
    Poniżej są notatki z kolejnych części jednego spotkania (w kolejności). Złóż z nich jedno końcowe \
    podsumowanie całego spotkania w wymaganym formacie, łącząc powtórzenia.
    """

    let provider: LLMProvider
    let config: LLMConfig
    var maxTokens = 16_000

    /// Dzieli transkrypt na części ≤ `limit` znaków, tnąc tylko między wypowiedziami.
    static func chunks(of transcript: String, limit: Int) -> [String] {
        guard transcript.count > limit else { return [transcript] }
        var parts: [String] = [], current = ""
        for line in transcript.components(separatedBy: "\n") {
            if !current.isEmpty, current.count + line.count + 1 > limit {
                parts.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n") + line
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    func summarize(transcript: String, prompt: String, progress: @Sendable (Double, String) -> Void) async throws -> String {
        let parts = Self.chunks(of: transcript, limit: config.provider.chunkCharacters)
        if parts.count == 1 {
            progress(0.1, "Podsumowanie (\(config.provider.displayName))")
            return try await provider.complete(system: prompt, user: "Transkrypt spotkania:\n\n\(transcript)", maxTokens: maxTokens)
        }
        var notes: [String] = []
        for (i, part) in parts.enumerated() {
            try Task.checkCancellation()
            progress(Double(i) / Double(parts.count + 1), "Podsumowanie części \(i + 1)/\(parts.count)")
            let instruction = String(format: Self.partialInstruction, i + 1, parts.count)
            notes.append(try await provider.complete(system: prompt, user: "\(instruction)\n\n\(part)", maxTokens: maxTokens))
        }
        progress(Double(parts.count) / Double(parts.count + 1), "Składanie podsumowania")
        let joined = notes.enumerated().map { "### Część \($0.offset + 1)\n\($0.element)" }.joined(separator: "\n\n")
        return try await provider.complete(system: prompt, user: "\(Self.finalInstruction)\n\n\(joined)", maxTokens: maxTokens)
    }

    /// Zapis do `summaries/<data>-<dostawca>-<model>.md` z nagłówkiem (historia — nic nie nadpisujemy).
    static func save(_ summary: String, meeting: Meeting, config: LLMConfig, store: MeetingStore = .shared) throws -> URL {
        let folder = store.summariesFolder(for: meeting.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let safeModel = config.model.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        let url = folder.appendingPathComponent("\(stamp.string(from: Date()))-\(config.provider.rawValue)-\(safeModel).md")
        let header = "> Podsumowanie wygenerowane przez \(config.provider.displayName) (\(config.model)) · \(PolishDate.short(Date()))\n\n"
        try (header + summary + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Najnowsze podsumowanie spotkania (pliki mają datę w nazwie).
    static func latest(for meetingID: String, store: MeetingStore = .shared) -> URL? {
        let folder = store.summariesFolder(for: meetingID)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted().last.map { folder.appendingPathComponent($0) }
    }
}
