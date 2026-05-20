import AppKit

final class TextInjector {
    enum Mode {
        case clipboardOnly
        case accessibilityPaste   // M3 implements paste; for M2 this falls through to clipboardOnly
    }

    private let mode: Mode

    init(mode: Mode) { self.mode = mode }

    func insert(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        switch mode {
        case .clipboardOnly:
            return
        case .accessibilityPaste:
            // Stub: M3 implements the CGEvent ⌘V + clipboard-restore flow.
            return
        }
    }
}
