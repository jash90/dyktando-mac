import AppKit

@MainActor
enum NudgeAlert {
    static func askToSetDefault(engine: EngineID, winRate: Double, prefs: Preferences) {
        let alert = NSAlert()
        alert.messageText = "Wygląda na to, że \(engine.rawValue) najlepiej ci pasuje"
        alert.informativeText = "Wybrałeś go w \(Int(winRate * 100))% z ostatnich 10 porównań. Ustawić jako domyślny?"
        alert.addButton(withTitle: "Tak, ustaw")
        alert.addButton(withTitle: "Nie teraz")
        if alert.runModal() == .alertFirstButtonReturn {
            prefs.defaultEngineID = engine.rawValue
        }
    }
}
