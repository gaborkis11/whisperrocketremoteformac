import SwiftUI

/// The panel while the host is working.
///
/// There is no progress to report — the host answers when it answers — so this
/// stage's job is to look like something is happening and to say, honestly,
/// which attempt this is when the first one did not take.
struct SendingStageView: View {
    var attempt: Int
    var maxAttempts: Int
    var reduceMotion: Bool

    /// The first attempt needs no explanation; a second one does.
    private var showsAttempt: Bool { attempt > 1 && maxAttempts > 1 }

    var body: some View {
        VStack(spacing: 4) {
            RocketLaunchView(reduceMotion: reduceMotion)

            Text(L.sendingTitle)
                .font(.callout)
                .foregroundStyle(.secondary)

            if showsAttempt {
                Text(L.sendingAttempt(attempt, of: maxAttempts))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(PanelMetrics.phaseAnimation(reduceMotion: reduceMotion), value: attempt)
    }
}
