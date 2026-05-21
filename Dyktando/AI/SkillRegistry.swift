import Foundation

/// Static registry of all available skills. Owners can extend the list here;
/// the LLM router gets each skill's id + description + params at prompt time.
enum SkillRegistry {
    static let all: [any Skill] = [
        SpotifySkill(),
        AppleMusicSkill(),
        WebSearchSkill(),
        OpenURLSkill(),
        OpenAppSkill(),
        ClaudeCodeSkill(),
        DiscordSendSkill(),
        SystemSkill(),
    ]

    static func skill(id: String) -> (any Skill)? {
        all.first { $0.id == id }
    }

    /// Compact, LLM-friendly catalogue used inside the system prompt.
    /// Format: `- id(param1, param2) — description`
    static var promptCatalogue: String {
        all.map { skill in
            let params = skill.parameters.map(\.name).joined(separator: ", ")
            return "- \(skill.id)(\(params)) — \(skill.description)"
        }.joined(separator: "\n")
    }

    /// Param hints expanded per-skill — surfaced to the model so it knows
    /// what string to put in each slot.
    static var promptParamHints: String {
        all.flatMap { skill in
            skill.parameters.map { param in
                "  \(skill.id).\(param.name): \(param.description)"
            }
        }.joined(separator: "\n")
    }
}
