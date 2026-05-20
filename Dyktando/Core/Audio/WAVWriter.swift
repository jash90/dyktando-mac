import AVFoundation

enum WAVWriter {
    static func write(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate,
                                   channels: 1,
                                   interleaved: false)!
        let file = try AVAudioFile(forWriting: url,
                                   settings: format.settings,
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw NSError(domain: "WAVWriter", code: 1)
        }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        try file.write(from: buf)
    }
}
