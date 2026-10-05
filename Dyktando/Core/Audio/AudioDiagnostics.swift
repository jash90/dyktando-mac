import Foundation

enum AudioDiagnostics {
    /// Same zera (nie cisza w pokoju, tylko dosłownie 0.0) = macOS nie daje aplikacji dźwięku:
    /// brak zgody na mikrofon albo brak uprawnienia `audio-input` przy hardened runtime.
    static func isDigitalSilence(_ samples: [Float]) -> Bool {
        !samples.contains { $0 != 0 }
    }

    static let digitalSilenceMessage =
        "Mikrofon zwraca ciszę — sprawdź uprawnienie: Ustawienia systemowe → Prywatność i ochrona → Mikrofon → Dyktando"
}
