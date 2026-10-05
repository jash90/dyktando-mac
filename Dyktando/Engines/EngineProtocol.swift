import AVFoundation
import Foundation

enum EngineID: String, Hashable, Codable, CaseIterable, Sendable {
    case parakeetTDTv3 = "parakeet-tdt-v3"
    case canary1bV2 = "canary-1b-v2"
    case whisperLargeV3Turbo = "whisper-large-v3-turbo"
    case whisperLargeV3 = "whisper-large-v3"
}

struct TranscriptionResult: Equatable, Sendable {
    let text: String
    let language: Locale
    let inferenceMillis: Int
    let confidence: Double?
}

enum LanguageMode: Equatable, Sendable {
    case single(Locale)
    case multilingualAuto(Set<Locale>)
    case mixed(primary: Locale, allowed: Set<Locale>)
}

enum EngineError: Error, Equatable, Sendable {
    case unsupportedLocale(String)
    case notInstalled
    case downloadFailed(String)
    case notAuthorized
}

protocol TranscriptionEngine: AnyObject, Sendable {
    var id: EngineID { get }
    var displayName: String { get }
    /// Krótki opis pod nazwą w Ustawieniach → Modele (np. jak model jest uruchamiany).
    var detail: String { get }
    var supportedLanguages: Set<Locale> { get }
    var isInstalled: Bool { get }

    func install(progress: @escaping @Sendable (Double) -> Void) async throws
    func uninstall() throws

    func transcribe(samples: [Float],
                    sampleRate: Double,
                    mode: LanguageMode) async throws -> TranscriptionResult
}

extension TranscriptionEngine {
    var detail: String { "" }
}
