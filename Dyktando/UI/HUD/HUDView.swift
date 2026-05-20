import SwiftUI

struct HUDView: View {
    @ObservedObject var state: HUDState

    var body: some View {
        HStack(spacing: 8) {
            icon
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .fixedSize()
    }

    @ViewBuilder private var icon: some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .listening:
            Image(systemName: "waveform")
        case .transcribing:
            ProgressView().controlSize(.small)
        case .preview:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder private var content: some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .listening:
            LevelBar(level: state.level).frame(width: 80, height: 12)
        case .transcribing:
            Text("transkrybuję").font(.callout)
        case .preview(let text):
            Text(text).font(.callout).lineLimit(1)
        }
    }
}

struct LevelBar: View {
    let level: Float
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.2))
                Capsule().fill(.tint)
                    .frame(width: geo.size.width * CGFloat(min(level * 4, 1)))
            }
        }
    }
}
