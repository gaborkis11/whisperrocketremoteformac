import SwiftUI

/// The live microphone meter: a row of bars that a new level pushes outwards
/// from the centre, so speech reads as a pulse travelling out rather than as
/// one bar twitching.
///
/// The history lives here, in the view, because the model only publishes *the
/// current level* — which is the right thing for it to publish. Keeping the
/// last few values is a presentation decision, and this is the presentation.
struct LevelBarsView: View {
    /// Smoothed 0…1 level from `AudioLevelMonitor`.
    var level: Double
    /// Smoothed 0…1 peak, drawn as the hold marker.
    var peak: Double
    var reduceMotion: Bool
    var barCount: Int = PanelMetrics.barCount

    /// Index 0 is the newest sample and sits in the middle; each older sample
    /// is one bar further out on both sides.
    @State private var history: [Double] = []

    private var ringCount: Int { barCount / 2 + 1 }

    var body: some View {
        ZStack(alignment: .bottom) {
            peakMarker
            HStack(alignment: .bottom, spacing: PanelMetrics.barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(.tint)
                        .frame(width: PanelMetrics.barWidth, height: height(at: index))
                }
            }
        }
        .frame(height: PanelMetrics.barMaxHeight)
        .animation(PanelMetrics.levelAnimation(reduceMotion: reduceMotion), value: history)
        .animation(PanelMetrics.levelAnimation(reduceMotion: reduceMotion), value: peak)
        .onAppear { history = Array(repeating: level, count: ringCount) }
        .onChange(of: level) { _, newValue in
            push(newValue)
        }
        .accessibilityElement()
        .accessibilityLabel(L.statusRecording)
        // A meter that reads a percentage is far more useful to VoiceOver than
        // nine unlabelled capsules.
        .accessibilityValue(Text(level, format: .percent.precision(.fractionLength(0))))
    }

    private var peakMarker: some View {
        Capsule(style: .continuous)
            .fill(.tint.quaternary)
            .frame(
                width: Double(barCount) * PanelMetrics.barWidth
                    + Double(barCount - 1) * PanelMetrics.barSpacing,
                height: 1
            )
            .padding(.bottom, max(0, min(1, peak)) * (PanelMetrics.barMaxHeight - 2))
            .accessibilityHidden(true)
    }

    private func push(_ value: Double) {
        guard history.count == ringCount else {
            history = Array(repeating: value, count: ringCount)
            return
        }
        history.removeLast()
        history.insert(value, at: 0)
    }

    /// Falls back to the live level for any bar the history has not reached
    /// yet, so a meter that is shown mid-recording starts at the right height
    /// instead of flat — and so a still render of this view is not a flat line.
    private func sample(at distance: Int) -> Double {
        distance < history.count ? history[distance] : level
    }

    private func height(at index: Int) -> Double {
        let distance = abs(index - barCount / 2)
        // The outer bars are damped a little, which keeps the row reading as a
        // shape instead of a picket fence.
        let damping = pow(0.86, Double(distance))
        let value = max(0, min(1, sample(at: distance))) * damping
        return PanelMetrics.barMinHeight
            + value * (PanelMetrics.barMaxHeight - PanelMetrics.barMinHeight)
    }
}
