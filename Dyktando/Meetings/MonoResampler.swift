import AVFoundation

/// Zamienia bufory z dowolnego źródła (mikrofon 48 kHz, tap systemowy stereo…) na 16 kHz mono Float32 —
/// format, w którym zapisujemy ścieżki spotkań i który przyjmują silniki transkrypcji.
/// Jeden obiekt na jedną ścieżkę; wywoływany z jednej kolejki naraz.
final class MonoResampler {
    static let sampleRate: Double = 16_000
    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: sampleRate,
                                            channels: 1,
                                            interleaved: false)!

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    func convert(_ pcm: AVAudioPCMBuffer) -> [Float] {
        guard pcm.frameLength > 0 else { return [] }
        if converter == nil || inputFormat != pcm.format {
            converter = AVAudioConverter(from: pcm.format, to: Self.targetFormat)
            inputFormat = pcm.format
        }
        guard let converter else { return [] }

        let ratio = Self.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount((Double(pcm.frameLength) * ratio).rounded(.up)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return [] }

        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, status in
            // Jak w AudioCapture: `.noDataNow`, nie `.endOfStream` — inaczej konwerter przechodzi
            // w stan końcowy i każde kolejne wywołanie zwraca zero próbek.
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return pcm
        }
        guard error == nil, let data = out.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
    }
}
