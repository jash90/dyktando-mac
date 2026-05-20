import SwiftUI
import AVFAudio

struct WelcomeStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill").font(.system(size: 48))
            Text("Dyktando").font(.largeTitle.bold())
            Text("Polskie dyktowanie głosowe na Macu, w pełni lokalne.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Dalej", action: next).keyboardShortcut(.return)
        }
    }
}

struct MicrophoneStep: View {
    @ObservedObject var permissions: PermissionsService
    let next: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill").font(.system(size: 48))
            Text("Mikrofon").font(.title.bold())
            Text("Potrzebujemy mikrofonu żeby nagrywać twój głos. Nagranie nigdy nie opuszcza twojego komputera.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            switch permissions.microphone {
            case .granted:
                Label("Mikrofon włączony", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Dalej", action: next).keyboardShortcut(.return)
            case .denied:
                Label("Mikrofon zablokowany", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                Text("Otwórz Ustawienia → Prywatność → Mikrofon i włącz Dyktando.")
                    .font(.caption).multilineTextAlignment(.center)
                Button("Dalej (w trybie tylko-schowek)", action: next)
            case .undetermined:
                Button("Włącz mikrofon") {
                    Task { _ = await permissions.requestMicrophone() }
                }
            @unknown default:
                Button("Dalej", action: next)
            }
        }
    }
}

struct AccessibilityStep: View {
    @ObservedObject var permissions: PermissionsService
    let next: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.tap.fill").font(.system(size: 48))
            Text("Accessibility").font(.title.bold())
            Text("Żeby wpisywać tekst pod kursorem w dowolnej aplikacji, Dyktando potrzebuje uprawnienia Accessibility. Bez niego tekst trafia tylko do schowka (musisz nacisnąć ⌘V).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if permissions.accessibility {
                Label("Accessibility włączone", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Dalej", action: next).keyboardShortcut(.return)
            } else {
                HStack {
                    Button("Otwórz Ustawienia systemowe") { permissions.openAccessibilityPane() }
                    Button("Pomiń (tryb schowka)", action: next)
                }
                Button("Sprawdź ponownie") { permissions.refreshAccessibility() }
                    .buttonStyle(.borderless)
            }
        }
    }
}

struct PickModelStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu").font(.system(size: 48))
            Text("Wybierz pierwszy model").font(.title.bold())
            Text("Apple Speech (pl-PL) działa od razu, bez pobierania. Whisper i Parakeet doinstalujesz później w Ustawieniach → Modele.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Użyj Apple Speech na początek", action: next).keyboardShortcut(.return)
        }
    }
}

struct TestShortcutStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.fill").font(.system(size: 48))
            Text("Test").font(.title.bold())
            Text("Przytrzymaj F5 i powiedz dowolne zdanie po polsku. Tekst powinien pojawić się pod kursorem (lub w schowku, jeśli nie włączyłeś Accessibility).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Dalej", action: next).keyboardShortcut(.return)
        }
    }
}

struct DoneStep: View {
    let finish: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.green)
            Text("Gotowe").font(.largeTitle.bold())
            Text("Możesz dyktować z dowolnej aplikacji.\nF5 = mów. ⌃⌥Space = przełącznik.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Zamknij", action: finish).keyboardShortcut(.return)
        }
    }
}
