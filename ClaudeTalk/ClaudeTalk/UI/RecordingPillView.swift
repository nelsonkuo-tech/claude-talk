import SwiftUI

struct RecordingPillView: View {
    var model: RecordingPillModel

    private let iconSize: CGFloat = 48
    private let barCount = 7
    private let maxBarHeight: CGFloat = 28
    private let barWidth: CGFloat = 3.5
    private let barSpacing: CGFloat = 3

    var body: some View {
        let isActive = model.state == .recording || model.state == .transcribing

        GlassEffectContainer {
            HStack(spacing: 10) {
                iconCircle
                waveformCapsule
            }
            .padding(6)
            .background {
                if isActive {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular, in: .capsule)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: model.state)
    }

    // MARK: - Icon Circle

    private var iconCircle: some View {
        iconImage
            .font(.system(size: 22, weight: .semibold))
            .frame(width: iconSize, height: iconSize)
            .glassEffect(.regular, in: .circle)
            .contentTransition(.symbolEffect(.replace))
    }

    @ViewBuilder
    private var iconImage: some View {
        switch model.state {
        case .idle:
            Image(systemName: "mic.fill")
                .foregroundStyle(.white)
        case .recording, .transcribing:
            Image(systemName: "mic.fill")
                .foregroundStyle(.green)
                .symbolEffect(.pulse, isActive: model.state == .transcribing)
        case .done:
            Image(systemName: "checkmark")
                .foregroundStyle(.green)
                .fontWeight(.bold)
        case .error:
            Image(systemName: "xmark")
                .foregroundStyle(.red)
                .fontWeight(.bold)
        }
    }

    // MARK: - Waveform Capsule

    private var waveformCapsule: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(.white)
                    .frame(
                        width: barWidth,
                        height: barHeight(for: i)
                    )
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .animation(.smooth(duration: 0.06), value: model.barLevels)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 6
        let level = model.barLevels[index]
        return max(minHeight, level * maxBarHeight)
    }
}
