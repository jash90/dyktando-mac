import AppKit

final class TextInjector {
    enum Mode {
        case clipboardOnly
        case accessibilityPaste
    }

    /// Delay between writing the new text to the pasteboard (and dispatching ⌘V)
    /// and restoring the previous contents. 60 ms is enough for the foreground
    /// app to consume the pasteboard via ⌘V.
    private static let restoreDelay: TimeInterval = 0.06

    let mode: Mode

    init(mode: Mode) { self.mode = mode }

    func insert(_ text: String) {
        let pb = NSPasteboard.general
        let snapshot = Self.snapshot(of: pb)
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard mode == .accessibilityPaste else { return }

        CGEventPaste.dispatch()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay) {
            Self.restore(snapshot, to: pb)
        }
    }

    // MARK: - Pasteboard preservation

    private struct PBItem {
        let types: [NSPasteboard.PasteboardType: Data]
    }

    private static func snapshot(of pb: NSPasteboard) -> [PBItem] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return PBItem(types: dict)
        }
    }

    private static func restore(_ snapshot: [PBItem], to pb: NSPasteboard) {
        pb.clearContents()
        let items: [NSPasteboardItem] = snapshot.map { snap in
            let item = NSPasteboardItem()
            for (type, data) in snap.types { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(items)
    }
}
