import SwiftUI

/// Name on the left, current state on the right. The mark fills in while the
/// microphone is open, so the panel header and the menu-bar icon are always
/// telling the same story.
struct PanelHeaderView: View {
    var phase: DictationPhase
    var reduceMotion: Bool

    var body: some View {
        HStack(spacing: 7) {
            RocketMarkView(
                style: phase.wantsFilledStatusIcon ? .filled : .outline,
                size: PanelMetrics.markSize
            )
            .foregroundStyle(phase == .recording ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
            .animation(PanelMetrics.phaseAnimation(reduceMotion: reduceMotion), value: phase)

            Text(L.appName)
                .font(.callout)
                .bold()

            Spacer(minLength: 8)

            Text(phase.localizedTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .combine)
    }
}
