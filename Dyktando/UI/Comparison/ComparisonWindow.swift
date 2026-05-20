import AppKit
import SwiftUI

@MainActor
final class ComparisonWindowController: NSWindowController {
    static let shared = ComparisonWindowController()
    private let state = ComparisonState()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Porównanie modeli"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: ComparisonView(state: state))
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(rows: [ComparisonRow], onPick: @escaping (ComparisonRow) -> Void) {
        state.rows = rows
        state.onPick = onPick
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class ComparisonState: ObservableObject {
    @Published var rows: [ComparisonRow] = []
    var onPick: ((ComparisonRow) -> Void)?
}

struct ComparisonView: View {
    @ObservedObject var state: ComparisonState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wybierz najlepszą transkrypcję")
                .font(.title2.bold())
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(state.rows, id: \.engineID) { row in
                        ComparisonRowView(row: row) {
                            state.onPick?(row)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 680, height: 320)
    }
}

struct ComparisonRowView: View {
    let row: ComparisonRow
    let onPick: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.engineID.rawValue).font(.subheadline.bold())
                    Spacer()
                    Text("\(row.result.inferenceMillis) ms")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(row.result.text.isEmpty ? "(brak)" : row.result.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Użyj tej", action: onPick)
                .controlSize(.small)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
