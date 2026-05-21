import AppKit
import ApplicationServices
import Foundation

/// Bulletproof launcher for the Claude Code CLI without AppleScript.
///
/// Flow:
///   1. `NSWorkspace.openApplication` — Terminal.app. No Apple Events needed.
///   2. Wait for it to become frontmost (with a hard timeout).
///   3. Synthesize ⌘N to guarantee a fresh window even if a previous session
///      is open. Uses CGEvent (Accessibility) which Dyktando already has.
///   4. Type the command, then press Return.
struct ClaudeCodeSkill: Skill {
    let id = "claude_code_launch"
    let description = "uruchom Claude Code w nowym oknie Terminala — bez parametrów, zawsze wpisuje 'claude'"
    let parameters: [SkillParameter] = []

    func run(params: [String: String]) async throws -> String {
        // The command is fixed: speech recognition mangles "Claude Code" into
        // "kloud kód"/"klałd code"/etc. and the LLM dutifully forwards the
        // garbled form. Hardcoding sidesteps the whole class of problems.
        let command = "claude"
        NSLog("[ClaudeCode] start")

        // 0) Hard-fail loudly when AX is missing — otherwise CGEvent posts
        //    silently no-op and the user just sees a blank Terminal.
        guard AXIsProcessTrusted() else {
            throw SkillError.execution("Brak uprawnienia Accessibility — Settings → Prywatność → Włącz Accessibility, potem zrestartuj Dyktando.")
        }

        // 1) Launch (or focus) Terminal.
        let terminalURL = Self.findTerminal()
        guard let terminalURL else {
            throw SkillError.execution("Nie znalazłem Terminal.app")
        }
        do {
            try await launch(at: terminalURL)
        } catch {
            throw SkillError.execution("Nie udało się uruchomić Terminala: \(error.localizedDescription)")
        }

        // 2) Wait for Terminal to become frontmost (≤ 2 s).
        let becameFront = await waitForFrontmost(bundleID: "com.apple.Terminal", timeoutMs: 2000)
        NSLog("[ClaudeCode] frontmost=%@", becameFront ? "yes" : "no")

        // 3) ⌘N — fresh window so we don't type into the user's existing session.
        NSLog("[ClaudeCode] sending ⌘N")
        await MainActor.run {
            CommandRunner.dispatch(keyCombo: KeyCombo(
                keyCode: 45, // 'n'
                modifiersRaw: NSEvent.ModifierFlags.command.rawValue,
                label: "⌘N"))
        }
        // Heavy zsh setups (oh-my-zsh, powerlevel10k, starship) routinely take
        // 2–3 s to render their prompt — anything we type before that gets
        // dropped. 3 s covers most real configurations.
        NSLog("[ClaudeCode] waiting 3000ms for prompt")
        try? await Task.sleep(for: .milliseconds(3000))

        // 4) Type command + Return.
        NSLog("[ClaudeCode] typing '%@'", command)
        await MainActor.run { CommandRunner.typeText(command) }
        try? await Task.sleep(for: .milliseconds(150))
        NSLog("[ClaudeCode] pressing return")
        await MainActor.run {
            CommandRunner.dispatch(keyCombo: KeyCombo(keyCode: 36, modifiersRaw: 0, label: "⏎"))
        }
        NSLog("[ClaudeCode] done")
        return "▶ Claude Code"
    }

    // MARK: - Launching

    private static func findTerminal() -> URL? {
        // Terminal moved between /Applications/Utilities and /System/Applications
        // across macOS versions; prefer the canonical Launch Services lookup.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            return url
        }
        for path in ["/System/Applications/Utilities/Terminal.app",
                     "/Applications/Utilities/Terminal.app"] {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func launch(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume() }
                }
            }
        }
    }

    @discardableResult
    private func waitForFrontmost(bundleID: String, timeoutMs: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMs) / 1000)
        while Date() < deadline {
            let front = await MainActor.run {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            }
            if front == bundleID { return true }
            try? await Task.sleep(for: .milliseconds(80))
        }
        return false
    }
}
