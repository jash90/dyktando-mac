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
        .background(background, in: Capsule())
        .overlay(
            Capsule().stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .opacity(opacity)
        .fixedSize()
        .animation(.easeInOut(duration: 0.18), value: state.phase)
    }

    private var background: AnyShapeStyle {
        switch state.phase {
        case .idle:         return AnyShapeStyle(.ultraThinMaterial)
        case .listening:    return AnyShapeStyle(.thinMaterial)
        case .transcribing: return AnyShapeStyle(.thinMaterial)
        case .preview:      return AnyShapeStyle(.thinMaterial)
        }
    }

    private var opacity: Double {
        switch state.phase {
        case .idle: return 0.75
        default:    return 1.0
        }
    }

    @ViewBuilder private var icon: some View {
        switch state.phase {
        case .idle:
            Image(systemName: "mic.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)
        case .listening:
            Image(systemName: "waveform")
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: true)
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
            Text("F5")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.5)
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
