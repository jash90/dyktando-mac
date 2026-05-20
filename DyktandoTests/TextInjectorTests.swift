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
}
