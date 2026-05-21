import Foundation

/// Posts a message to a configured Discord webhook URL. The URL lives in
/// Preferences (Settings → AI → Discord), so the skill itself is stateless.
///
/// Typical phrasing: "napisz do Claude zrób mi taska na jutro" → Gemma fills
/// `message: "zrób mi taska na jutro"` and we POST it. Whatever Discord bot
/// (e.g. Claude Code MCP) is listening on the channel picks it up.
struct DiscordSendSkill: Skill {
    let id = "discord_send"
    let description = "wyślij wiadomość na Discord przez webhook (np. żeby zlecić zadanie Claude Code)"
    let parameters: [SkillParameter] = [
        SkillParameter("message", "treść wiadomości do wysłania")
    ]

    func run(params: [String: String]) async throws -> String {
        let message = try require("message", in: params)
        let urlString = await MainActor.run { Preferences.shared.discordWebhookURL }
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            throw SkillError.execution("Skonfiguruj Discord webhook w Settings → AI")
        }

        let payload: [String: Any] = [
            "content": message,
            "username": "Dyktando",
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw SkillError.execution("Discord odrzucił: \(snippet)")
        }
        // Trim long previews for the HUD.
        let preview = message.count > 60 ? String(message.prefix(60)) + "…" : message
        return "💬 Discord · \(preview)"
    }
}
