import SwiftUI

/// The acknowledgement. On screen for about a second and a half, so it has to
/// answer one question in one glance: *where did my text go?*
///
/// The transcribed text itself is deliberately not shown — it is already on the
/// clipboard and usually already in the app the user was typing into, and
/// showing it would turn a glance into a read.
struct DoneStageView: View {
    var summary: DictationSummary
    var reduceMotion: Bool

    @State private var landed = false

    var body: some View {
        VStack(spacing: PanelMetrics.rowSpacing) {
            Image(systemName: "checkmark.circle.fill")
                // A text style rather than a point size, so it grows with
                // Dynamic Type instead of staying a 30 pt dot next to 24 pt text.
                .font(.largeTitle)
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(landed ? 1 : 0.7)
                .opacity(landed ? 1 : 0)
                .animation(
                    reduceMotion ? PanelMetrics.reducedMotionChange : .bouncy(duration: 0.4),
                    value: landed
                )
                .accessibilityHidden(true)

            Text(summary.delivery.localizedHeadline)
                .font(.headline)

            if summary.mode == .compose {
                // The host answered instead of transcribing, so the text will
                // not match what was said. Worth a line.
                Label(L.doneComposed, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }

            if let explanation = summary.delivery.localizedExplanation {
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L.doneCharacters(summary.characterCount))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { landed = true }
        .accessibilityElement(children: .combine)
    }
}
