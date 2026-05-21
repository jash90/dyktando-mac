import Foundation

/// Sends post-processed user speech to Gemma via Ollama, asks the model to
/// pick one of the registered skills or return `null` for "this is dictation,
/// just insert as text". The router stays *very* opinionated about the JSON
/// shape so we can decode reliably even on small models.
struct IntentRouter {
    let client: OllamaClient

    init(client: OllamaClient) {
        self.client = client
    }

    enum Decision: Equatable {
        case skill(id: String, params: [String: String])
        case none
    }

    func decide(text: String) async throws -> Decision {
        let system = Self.systemPrompt()
        let user = "Wypowiedź użytkownika: \"\(text)\""

        NSLog("[AI] router → %@", text)
        let raw = try await client.generate(system: system, user: user, jsonMode: true)
        NSLog("[AI] router ← %@", raw)

        guard let data = raw.data(using: .utf8) else { return .none }
        let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        // Accept either {"skill": null} or {"skill": "id", "params": {...}}.
        guard let skillID = parsed["skill"] as? String, !skillID.isEmpty else {
            return .none
        }
        let params = (parsed["params"] as? [String: Any]) ?? [:]
        let stringParams: [String: String] = params.reduce(into: [:]) { acc, pair in
            if let s = pair.value as? String { acc[pair.key] = s }
            else if let n = pair.value as? NSNumber { acc[pair.key] = n.stringValue }
        }
        return .skill(id: skillID, params: stringParams)
    }

    // MARK: - Prompt

    static func systemPrompt() -> String {
        """
        Jesteś routerem komend głosowych dla użytkownika piszącego po polsku. \
        Dostajesz wypowiedź zdyktowaną mikrofonem. Twoim jedynym zadaniem jest \
        zdecydować czy to jest komenda do wykonania (z poniższej listy umiejętności), \
        czy zwykły tekst do wstawienia.

        Dostępne umiejętności:
        \(SkillRegistry.promptCatalogue)

        Parametry:
        \(SkillRegistry.promptParamHints)

        Zwróć WYŁĄCZNIE poprawny JSON, jeden z tych dwóch kształtów:

        1) Gdy to komenda:
        {"skill": "<id>", "params": {"<param>": "<wartość>", ...}}

        2) Gdy to zwykła dyktowana treść (np. e-mail, notatka, wpis):
        {"skill": null}

        Reguły:
        - NIE zmyślaj parametrów których nie ma w wypowiedzi.
        - Jeśli się wahasz, zwróć {"skill": null} — lepiej wstawić jako tekst.
        - Nazwy własne (artyści, aplikacje, miasta) zostaw w oryginale.
        - Krótkie zwroty typu "tak", "ok", "dziękuję" → {"skill": null}.
        - Dla `discord_send`: usuń słowa rozpoczynające komendę ("napisz do …", "powiedz …", "wyślij do …") z pola `message`. \
          Zostaw TYLKO właściwą treść do wysłania.

        Przykłady ekstrakcji `message`:
          "napisz do Claude zrób mi taska na jutro" → message: "zrób mi taska na jutro"
          "powiedz Claudowi że jutro jest deadline" → message: "że jutro jest deadline"
          "wyślij do Claude listę zakupów: chleb, masło, ser" → message: "listę zakupów: chleb, masło, ser"
        """
    }
}
