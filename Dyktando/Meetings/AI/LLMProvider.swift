import Foundation

/// Dostawcy AI do podsumowań spotkań. OpenAI, OpenRouter i Z.AI mówią protokołem OpenAI Chat
/// Completions; Anthropic ma własne Messages API.
enum AIProviderID: String, CaseIterable, Identifiable, Codable, Sendable {
    case anthropic, openai, openrouter, zai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic:  return "Anthropic"
        case .openai:     return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .zai:        return "Z.AI (GLM)"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic:  return "https://api.anthropic.com/v1"
        case .openai:     return "https://api.openai.com/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .zai:        return "https://api.z.ai/api/paas/v4"
        }
    }

    /// Domyślny model tylko tam, gdzie jest pewny; u pozostałych użytkownik wybiera z listy modeli
    /// pobranej przez „Testuj połączenie” (nazwy modeli tych dostawców często się zmieniają).
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-5-5"
        default:         return ""
        }
    }

    var modelPlaceholder: String {
        switch self {
        case .anthropic:  return "claude-opus-5-5"
        case .openai:     return "wybierz po „Testuj połączenie”"
        case .openrouter: return "np. anthropic/claude-opus-5-5"
        case .zai:        return "np. glm-5.3"
        }
    }

    /// Ile znaków transkryptu mieści się w jednym zapytaniu (zachowawczo; polski ≈ 3 znaki/token).
    /// Claude ma okno 1M tokenów; dla pozostałych nie znamy modelu z góry — ostrożnie ~60k tokenów.
    var chunkCharacters: Int {
        self == .anthropic ? 1_200_000 : 180_000
    }
}

struct LLMError: LocalizedError, Equatable {
    var message: String
    var retryable = false
    var errorDescription: String? { message }
}

protocol LLMProvider: Sendable {
    func complete(system: String, user: String, maxTokens: Int) async throws -> String
    func listModels() async throws -> [String]
}

struct LLMConfig: Sendable {
    var provider: AIProviderID
    var apiKey: String
    var model: String
    var baseURL: String

    func makeProvider(session: URLSession = .shared) -> LLMProvider {
        switch provider {
        case .anthropic: return AnthropicProvider(config: self, session: session)
        default:         return OpenAICompatibleProvider(config: self, session: session)
        }
    }

    var base: URL {
        URL(string: baseURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            ?? URL(string: provider.defaultBaseURL)!
    }
}

// MARK: - Wspólne HTTP

enum LLMHTTP {
    static let timeout: TimeInterval = 600

    /// Wysyła zapytanie z ponawianiem dla 429 / 5xx / 529 (przeciążenie) i błędów sieci.
    static func send(_ request: URLRequest, session: URLSession, attempts: Int = 3) async throws -> [String: Any] {
        var lastError: Error = LLMError(message: "Brak odpowiedzi")
        for attempt in 0..<attempts {
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                if (200..<300).contains(status) { return json }
                let error = httpError(status: status, json: json, body: data)
                guard error.retryable, attempt < attempts - 1 else { throw error }
                lastError = error
                let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
                try await Task.sleep(nanoseconds: UInt64((retryAfter ?? pow(2, Double(attempt + 1))) * 1_000_000_000))
            } catch let error as LLMError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = LLMError(message: "Błąd sieci: \(error.localizedDescription)", retryable: true)
                guard attempt < attempts - 1 else { throw lastError }
                try await Task.sleep(nanoseconds: UInt64(pow(2, Double(attempt + 1)) * 1_000_000_000))
            }
        }
        throw lastError
    }

    static func httpError(status: Int, json: [String: Any], body: Data) -> LLMError {
        let detail = ((json["error"] as? [String: Any])?["message"] as? String)
            ?? (json["error"] as? String)
            ?? (json["message"] as? String)
            ?? String(data: body.prefix(300), encoding: .utf8) ?? ""
        switch status {
        case 401, 403: return LLMError(message: "Klucz API odrzucony (\(status)): \(detail)")
        case 402:      return LLMError(message: "Brak środków na koncie dostawcy (402): \(detail)")
        case 404:      return LLMError(message: "Nie znaleziono (404) — sprawdź model i adres API: \(detail)")
        case 429:      return LLMError(message: "Limit zapytań (429): \(detail)", retryable: true)
        case 500...599: return LLMError(message: "Błąd serwera dostawcy (\(status)): \(detail)", retryable: true)
        default:       return LLMError(message: "Błąd \(status): \(detail)")
        }
    }

    static func jsonRequest(url: URL, body: [String: Any], headers: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// MARK: - OpenAI / OpenRouter / Z.AI

struct OpenAICompatibleProvider: LLMProvider {
    let config: LLMConfig
    let session: URLSession

    var headers: [String: String] {
        var h = ["Authorization": "Bearer \(config.apiKey)"]
        if config.provider == .openrouter {
            h["X-Title"] = "Dyktando"  // atrybucja w panelu OpenRouter (opcjonalna)
        }
        return h
    }

    func makeRequest(system: String, user: String, maxTokens: Int) throws -> URLRequest {
        var body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        // Nowsze modele OpenAI przyjmują tylko max_completion_tokens; OpenRouter i Z.AI — max_tokens.
        body[config.provider == .openai ? "max_completion_tokens" : "max_tokens"] = maxTokens
        return try LLMHTTP.jsonRequest(url: config.base.appendingPathComponent("chat/completions"), body: body, headers: headers)
    }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        let json = try await LLMHTTP.send(try makeRequest(system: system, user: user, maxTokens: maxTokens), session: session)
        return try Self.parseCompletion(json)
    }

    static func parseCompletion(_ json: [String: Any]) throws -> String {
        guard let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else {
            throw LLMError(message: "Nieoczekiwana odpowiedź dostawcy (brak choices)")
        }
        let text = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            let reason = choice["finish_reason"] as? String ?? "?"
            throw LLMError(message: reason == "length" ? "Model skończył się na limicie długości — brak treści"
                                                       : "Pusta odpowiedź modelu (finish_reason: \(reason))")
        }
        return text
    }

    func listModels() async throws -> [String] {
        var request = URLRequest(url: config.base.appendingPathComponent("models"))
        request.timeoutInterval = 30
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else { throw LLMHTTP.httpError(status: status, json: json, body: data) }
        return ((json["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }.sorted()
    }
}

// MARK: - Anthropic (Messages API, surowe HTTP — Swift nie ma oficjalnego SDK)

struct AnthropicProvider: LLMProvider {
    let config: LLMConfig
    let session: URLSession

    static let version = "2023-06-01"
    /// Odmowa klasyfikatora bezpieczeństwa → API samo powtarza zapytanie na zalecanym modelu zastępczym.
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    /// Modele z serwerowym `fallbacks: "default"` (rodzina Opus 5 / Opus 5.5 / Sonnet 5.5 / Fable 5.1).
    static let fallbackModels: Set<String> = ["claude-opus-5", "claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-1"]

    /// `output_config.effort` — błąd 400 na Haiku 4.5, Sonnet 4.5 i starszych; obsługują go nowsze modele.
    static func supportsEffort(_ model: String) -> Bool {
        let supported = ["claude-fable-", "claude-mythos-", "claude-opus-5", "claude-sonnet-5",
                         "claude-opus-4-5", "claude-opus-4-6", "claude-opus-4-7", "claude-opus-4-8", "claude-sonnet-4-6"]
        return supported.contains { model.hasPrefix($0) }
    }

    /// Fallback tylko do oficjalnego API Anthropic (bramki/proxy pod innym adresem mogą go nie znać).
    var usesFallbacks: Bool {
        Self.fallbackModels.contains(config.model) && config.base.host == "api.anthropic.com"
    }

    var headers: [String: String] {
        var h = ["x-api-key": config.apiKey, "anthropic-version": Self.version]
        if usesFallbacks { h["anthropic-beta"] = Self.fallbackBeta }
        return h
    }

    func makeRequest(system: String, user: String, maxTokens: Int) throws -> URLRequest {
        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        // Claude Opus 5.5 ma domyślnie effort „medium” — ustawiamy jawnie tam, gdzie model to obsługuje.
        if Self.supportsEffort(config.model) { body["output_config"] = ["effort": "medium"] }
        if usesFallbacks { body["fallbacks"] = "default" }
        return try LLMHTTP.jsonRequest(url: config.base.appendingPathComponent("messages"), body: body, headers: headers)
    }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        let json = try await LLMHTTP.send(try makeRequest(system: system, user: user, maxTokens: maxTokens), session: session)
        return try Self.parseMessage(json)
    }

    static func parseMessage(_ json: [String: Any]) throws -> String {
        let stopReason = json["stop_reason"] as? String
        // Odmowa przychodzi jako HTTP 200 — sprawdzamy stop_reason, zanim przeczytamy treść.
        if stopReason == "refusal" {
            let category = (json["stop_details"] as? [String: Any])?["category"] as? String
            throw LLMError(message: "Model odmówił odpowiedzi\(category.map { " (kategoria: \($0))" } ?? "")")
        }
        let text = ((json["content"] as? [[String: Any]]) ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw LLMError(message: stopReason == "max_tokens" ? "Model skończył się na limicie długości — brak treści"
                                                               : "Pusta odpowiedź modelu (stop_reason: \(stopReason ?? "?"))")
        }
        return text
    }

    func listModels() async throws -> [String] {
        var request = URLRequest(url: config.base.appendingPathComponent("models"))
        request.timeoutInterval = 30
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else { throw LLMHTTP.httpError(status: status, json: json, body: data) }
        return ((json["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
    }
}
