import Foundation
import AVFoundation
import XCTest
@testable import Dyktando

enum TestFixtures {
    static func polishThreeSeconds() throws -> [Float] {
        try loadFixture(name: "three-seconds-pl", ext: "caf")
    }

    private static func loadFixture(name: String, ext: String) throws -> [Float] {
        guard let url = Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "TestFixtures",
                          code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Fixture \(name).\(ext) not found in test bundle"])
        }
        let file = try AVAudioFile(forReading: url)
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                   frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let count = Int(buf.frameLength)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: count))
    }

    private final class BundleAnchor {}
}
