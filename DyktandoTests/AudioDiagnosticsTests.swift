import XCTest
import Security
@testable import Dyktando

final class AudioDiagnosticsTests: XCTestCase {
    func test_digitalSilence_onlyForExactZeros() {
        XCTAssertTrue(AudioDiagnostics.isDigitalSilence([Float](repeating: 0, count: 16_000)))
        XCTAssertTrue(AudioDiagnostics.isDigitalSilence([]))
        // Cicha, ale prawdziwa cisza w pokoju to nie „same zera” — tę oceni model.
        var quiet = [Float](repeating: 0, count: 16_000)
        quiet[8_000] = 0.00001
        XCTAssertFalse(AudioDiagnostics.isDigitalSilence(quiet))
    }

    /// Regresja z 0.2.0–0.2.2: hardened runtime bez `audio-input` = mikrofon zwraca same zera,
    /// macOS nawet nie pyta o zgodę. Test host to sama aplikacja, więc sprawdzamy jej podpis.
    func test_app_isEntitledForMicrophone() throws {
        guard let task = SecTaskCreateFromSelf(nil) else { throw XCTSkip("SecTask niedostępny") }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.device.audio-input" as CFString, nil)
        XCTAssertEqual(value as? Bool, true, "brak com.apple.security.device.audio-input w podpisie aplikacji")
    }
}
