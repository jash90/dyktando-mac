import XCTest
import AppKit
@testable import Dyktando

@MainActor
final class TextInjectorTests: XCTestCase {
    func test_clipboardMode_writesPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        let injector = TextInjector(mode: .clipboardOnly)
        injector.insert("hello world")
        XCTAssertEqual(pb.string(forType: .string), "hello world")
    }

    func test_clipboardMode_overwritesPrevious() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("first", forType: .string)
        let injector = TextInjector(mode: .clipboardOnly)
        injector.insert("second")
        XCTAssertEqual(pb.string(forType: .string), "second")
    }

    func test_clipboardMode_emptyString_clearsPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("preexisting", forType: .string)
        let injector = TextInjector(mode: .clipboardOnly)
        injector.insert("")
        XCTAssertEqual(pb.string(forType: .string), "")
    }

    func test_pasteMode_writesPasteboardImmediately() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("original", forType: .string)
        let injector = TextInjector(mode: .accessibilityPaste)
        injector.insert("dictated")
        // Right after the call, the new text is on the pasteboard so CGEventPaste can paste it.
        XCTAssertEqual(pb.string(forType: .string), "dictated")
    }

    func test_pasteMode_restoresClipboardAfterDelay() async throws {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("original", forType: .string)

        let injector = TextInjector(mode: .accessibilityPaste)
        injector.insert("dictated")

        // Wait longer than the restore delay (60 ms in impl) plus headroom.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(pb.string(forType: .string), "original")
    }
}
