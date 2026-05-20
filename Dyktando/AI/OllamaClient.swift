import Foundation

/// Minimal HTTP client for Ollama's `/api/generate` endpoint.
/// Non-streaming JSON-mode requests are used so we can parse a single
/// structured response without dealing with NDJSON chunking.
struct OllamaClient {
    let host: URL
    let model: String
    let timeout: TimeInterval

    init(host: URL = URL(string: "http://localhost:11434")!,
         model: String = "gemma4:latest",
         timeout: TimeInterval = 12) {
        self.host = host
        self.model = model
        self.timeout = timeout
    }

    struct GenerateResponse: Decodable {
        let response: String
        let done: Bool
    }

    /// Sends one prompt and returns the raw `response` field (typically a JSON
    /// document when `format: "json"` is requested).
    func generate(system: String,
                  user: String,
                  jsonMode: Bool = true,
                  temperature: Double = 0.1) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "prompt": user,
            "system": system,
            "stream": false,
            "options": ["temperature": temperature],
        ]
        if jsonMode { body["format"] = "json" }

        var request = URLRequest(url: host.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OllamaError.badStatus(snippet)
        }
        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        return decoded.response
    }

    /// Simple health check used by Settings → AI ("Sprawdź połączenie").
    func ping() async throws -> [String] {
        var request = URLRequest(url: host.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OllamaError.badStatus(String(data: data, encoding: .utf8) ?? "")
        }
        struct TagsResponse: Decodable {
            struct ModelEntry: Decodable { let name: String }
            let models: [ModelEntry]
        }
        let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
        return tags.models.map(\.name)
    }
}

enum OllamaError: LocalizedError {
    case badStatus(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let body): return "Ollama HTTP error: \(body)"
        case .decode(let info):    return "Ollama decode error: \(info)"
        }
    }
}
