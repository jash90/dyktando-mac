import Foundation

/// One concrete capability that an LLM router can pick. Every skill has a
/// stable id, a one-line description for the prompt, and a JSON-schema-ish
/// listing of its required parameters. Skills are stateless and short-lived
/// per invocation.
protocol Skill: Sendable {
    /// Stable identifier the LLM must echo back in its routing JSON.
    var id: String { get }

    /// Human-prompt description used in the system prompt:
    /// "spotify_play — odtwórz utwór/album na Spotify".
    var description: String { get }

    /// Required parameters with short hints. Keys are case-sensitive.
    var parameters: [SkillParameter] { get }

    /// Executes the skill. Throws on validation or runtime failure.
    /// Returns a short user-facing preview shown in the HUD.
    func run(params: [String: String]) async throws -> String
}

struct SkillParameter {
    let name: String
    let description: String
    let required: Bool

    init(_ name: String, _ description: String, required: Bool = true) {
        self.name = name
        self.description = description
        self.required = required
    }
}

enum SkillError: LocalizedError {
    case missingParam(String)
    case invalidParam(String, String)
    case execution(String)

    var errorDescription: String? {
        switch self {
        case .missingParam(let n):       return "Brakuje parametru '\(n)'"
        case .invalidParam(let n, let v): return "Niepoprawny parametr \(n)='\(v)'"
        case .execution(let m):           return m
        }
    }
}

/// Convenience for skill implementations.
extension Skill {
    func require(_ name: String, in params: [String: String]) throws -> String {
        guard let v = params[name], !v.isEmpty else { throw SkillError.missingParam(name) }
        return v
    }
}
