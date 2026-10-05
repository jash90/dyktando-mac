import AVFoundation
import AudioToolbox
import CoreAudio

/// Ścieżka „Ja”: mikrofon wybrany w Ustawieniach → Audio, własny AVAudioEngine —
/// niezależny od dyktowania (F5 dalej działa w trakcie spotkania).
final class MicTrackRecorder {
    private var engine: AVAudioEngine?
    private let resampler = MonoResampler()
    private let writer: SegmentedAudioWriter

    init(writer: SegmentedAudioWriter) { self.writer = writer }

    func start() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        AudioDevices.applySelectedDevice(to: input)
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw NSError(domain: "Dyktando.Meeting", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Mikrofon niedostępny (0 kanałów) — sprawdź uprawnienie do mikrofonu."])
        }
        let resampler = self.resampler, writer = self.writer
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { pcm, _ in
            writer.append(resampler.convert(pcm))
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        NSLog("[Meeting] mic track started (%.0f Hz, %d ch)", format.sampleRate, format.channelCount)
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }
}

/// Ścieżka „Rozmówcy”: dźwięk odtwarzany przez wszystkie aplikacje (Meet, Zoom, Teams…) poza samym
/// Dyktandem, przez Core Audio process tap (macOS 14.4+). Wymaga zgody „Nagrywanie dźwięku systemowego”
/// (NSAudioCaptureUsageDescription). Odczyt: tap → prywatne aggregate device → IOProc.
/// Wzorzec: github.com/insidegui/AudioCap.
@available(macOS 14.4, *)
final class SystemAudioRecorder {
    enum TapError: LocalizedError {
        case coreAudio(String, OSStatus)
        var errorDescription: String? {
            switch self {
            case .coreAudio(let what, let status): return "Dźwięk systemowy: \(what) (błąd \(status))"
            }
        }
    }

    private let writer: SegmentedAudioWriter
    private let resampler = MonoResampler()
    private let queue = DispatchQueue(label: "dyktando.meeting.systemtap", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    /// Ile sekund z rzędu tap oddaje cyfrową ciszę — przy braku zgody macOS podaje same zera
    /// (tak samo, gdy nic nie gra, więc to tylko wskazówka). Zmieniane wyłącznie na `queue`.
    private var silentSeconds: Double = 0
    private var buffers = 0
    var consecutiveSilentSeconds: Double { queue.sync { silentSeconds } }
    /// Ile buforów oddał tap. 0 po kilku sekundach = tap „martwy” — typowo utworzony, zanim
    /// użytkownik zgodził się na nagrywanie dźwięku systemowego; trzeba go utworzyć od nowa.
    var buffersReceived: Int { queue.sync { buffers } }

    init(writer: SegmentedAudioWriter) { self.writer = writer }

    func start() throws {
        let own = Self.processObject(for: getpid())
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: own.map { [$0] } ?? [])
        description.uuid = UUID()
        description.name = "Dyktando — nagrywanie spotkania"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "nie udało się utworzyć tapu")
        tapID = tap

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                       mScope: kAudioObjectPropertyScopeGlobal,
                                                       mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &asbd), "brak formatu tapu")
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            throw TapError.coreAudio("nieobsługiwany format tapu", -1)
        }

        let outputUID = try Self.defaultOutputDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Dyktando — tap spotkania",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var aggregateDevice = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateDevice),
                  "nie udało się utworzyć urządzenia zbiorczego")
        aggregateID = aggregateDevice

        let resampler = self.resampler, writer = self.writer
        var proc: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, queue) { [weak self] _, input, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
            let samples = resampler.convert(buffer)
            writer.append(samples)
            self?.trackSilence(samples)
        }, "nie udało się podpiąć odczytu")
        procID = proc
        try check(AudioDeviceStart(aggregateID, procID), "nie udało się wystartować")
        NSLog("[Meeting] system tap started (%.0f Hz, %d ch, output=%@)", format.sampleRate, format.channelCount, outputUID)
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func trackSilence(_ samples: [Float]) {
        buffers += 1
        let seconds = Double(samples.count) / MonoResampler.sampleRate
        silentSeconds = samples.contains { $0 != 0 } ? 0 : silentSeconds + seconds
    }

    // MARK: - Core Audio

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw TapError.coreAudio(what, status) }
    }

    static func processObject(for pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func defaultOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw TapError.coreAudio("brak domyślnego wyjścia", status) }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        status = withUnsafeMutablePointer(to: &uid) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0) }
        guard status == noErr, let uid else { throw TapError.coreAudio("brak UID wyjścia", status) }
        return uid.takeRetainedValue() as String
    }
}
