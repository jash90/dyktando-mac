import AVFoundation
import Speech

final class AppleSpeechEngine: TranscriptionEngine, @unchecked Sendable {
    let id: EngineID = .appleSpeechPL
    let displayName = "Apple Speech (pl-PL)"
    let supportedLanguages: Set<Locale> = [Locale(identifier: "pl-PL")]

    var isInstalled: Bool {
        guard SFSpeechRecognizer.supportedLocales().contains(Locale(identifier: "pl-PL")) else {
            return false
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pl-PL")) else {
            return false
        }
        return recognizer.supportsOnDeviceRecognition
    }

    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1)
    }

    func uninstall() throws { /* system-provided */ }

    func transcribe(samples: [Float],
                    sampleRate: Double,
                    mode: LanguageMode) async throws -> TranscriptionResult {
        try await Self.requestAuthorizationIfNeeded()

        let locale = Self.locale(for: mode)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw EngineError.unsupportedLocale(locale.identifier)
        }
        guard recognizer.isAvailable else {
            throw EngineError.notInstalled
        }

        // Guard against on-device model not yet downloaded
        if !recognizer.supportsOnDeviceRecognition {
            throw EngineError.notInstalled
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true

        let pcm = try Self.makeBuffer(samples: samples, sampleRate: sampleRate)
        let start = Date()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<TranscriptionResult, Error>) in
            var finished = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                if let error {
                    finished = true
                    // Map on-device-not-available errors to .notInstalled
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 1101 {
                        cont.resume(throwing: EngineError.notInstalled)
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                guard let result, result.isFinal else { return }
                finished = true
                let conf = result.bestTranscription.segments.first.map { Double($0.confidence) }
                cont.resume(returning: TranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    language: locale,
                    inferenceMillis: Int(Date().timeIntervalSince(start) * 1000),
                    confidence: conf))
            }
            request.append(pcm)
            request.endAudio()
            _ = task
        }
    }

    private static func requestAuthorizationIfNeeded() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return }
        let new = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard new == .authorized else { throw EngineError.notAuthorized }
    }

    private static func locale(for mode: LanguageMode) -> Locale {
        switch mode {
        case .single(let l):
            return l
        case .multilingualAuto(let langs), .mixed(_, let langs):
            return langs.first { $0.identifier.hasPrefix("pl") } ?? Locale(identifier: "pl-PL")
        }
    }

    private static func makeBuffer(samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate,
                                   channels: 1,
                                   interleaved: false)!
        guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw EngineError.notInstalled
        }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        return buf
    }
}
