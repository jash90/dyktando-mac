import Foundation
import SwiftUI

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("defaultEngineID")
    var defaultEngineID: String = EngineID.parakeetTDTv3.rawValue

    @AppStorage("languageModeRaw")
    var languageModeRaw: String = "single:pl-PL"

    /// UID urządzenia wejściowego z Core Audio; pusty = domyślne wejście systemu (Ustawienia → Audio).
    @AppStorage(AudioDevices.preferenceKey)
    var inputDeviceUID: String = ""

    // MARK: Spotkania

    /// Silnik do transkrypcji spotkań (może być inny niż do dyktowania, np. dokładniejszy Whisper).
    @AppStorage("meetingEngineID")
    var meetingEngineID: String = EngineID.parakeetTDTv3.rawValue

    /// Rozpoznawanie poszczególnych rozmówców (diaryzacja ścieżki dźwięku z aplikacji).
    @AppStorage("meetingDiarization")
    var meetingDiarization: Bool = true

    /// Transkrypcja startuje sama po zatrzymaniu nagrywania.
    @AppStorage("meetingAutoTranscribe")
    var meetingAutoTranscribe: Bool = true

    /// Podsumowanie AI startuje samo po transkrypcji (wysyła transkrypt do dostawcy) — domyślnie wyłączone.
    @AppStorage("meetingAutoSummarize")
    var meetingAutoSummarize: Bool = false

    /// Po ilu dniach usuwać audio spotkań (transkrypt i podsumowania zostają). 0 = nigdy.
    @AppStorage("meetingAudioRetentionDays")
    var meetingAudioRetentionDays: Int = 30

    /// Podpowiedź „Wykryto spotkanie — nagrać?”, gdy aplikacja do rozmów zacznie używać mikrofonu.
    @AppStorage("meetingDetectionPrompt")
    var meetingDetectionPrompt: Bool = true

    @AppStorage("hudEnabled")
    var hudEnabled: Bool = true

    @AppStorage("launchAtLogin")
    var launchAtLogin: Bool = false

    private init() {}
}
