import XCTest
import AVFoundation
@testable import Dyktando

final class WAVWriterTests: XCTestCase {
    func test_roundTrip_writesAndReadsSamples() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wavtest-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let samples: [Float] = (0..<8000).map { Float(sin(Double($0) * 0.01)) }
        try WAVWriter.write(samples, sampleRate: 16_000, to: url)

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(Int(file.length), 8000)
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
    }
}
