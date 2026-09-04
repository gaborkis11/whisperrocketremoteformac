import SwiftUI

/// The capsule's two lines of words: what is happening, and the one number or
/// sentence that qualifies it.
///
/// A fixed width, set by ``CapsuleMetrics/textColumnWidth``, so the waveform
/// lane beside it does not shuffle sideways every time the counter gains a
/// digit or a warning appears.
struct CapsuleTextColumn: View {
    var title: String
    /// Recording gets the larger title: it is the stage a person glances at
    /// while talking, from across the desk.
    var isPrimary: Bool
    var subline: Subline

    /// The five things the second line is ever allowed to be.
    enum Subline: Equatable {
        /// Seconds captured so far.
        case counter(TimeInterval)
        /// The last 30 s of the ceiling, in the counter's place.
        case countdown(Int)
        /// Something the user should know while they keep talking — stored mode.
        case warning(String)
        /// Plain supporting text: the paste hint, the failure's reassurance.
        case note(String)
        /// The rotating line under the rocket while the host thinks.
        case joke(reduceMotion: Bool)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: isPrimary ? 15 : 14, weight: .semibold))
                .foregroundStyle(CapsuleMetrics.ink)
                .lineLimit(1)

            sublineView
                .lineLimit(1)
        }
        .frame(width: CapsuleMetrics.textColumnWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var sublineView: some View {
        switch subline {
        case .counter(let elapsed):
            Text(Duration.seconds(elapsed), format: .time(pattern: .minuteSecond))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CapsuleMetrics.amber)

        case .countdown(let seconds):
            Text(L.countdown(seconds))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                // The last five seconds go red; before that it is a heads-up,
                // not an alarm.
                .foregroundStyle(seconds <= 5 ? CapsuleMetrics.danger : CapsuleMetrics.amber)

        case .warning(let text):
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CapsuleMetrics.subdued)
                // A Hungarian warning is half again as long as its English
                // original; shrinking a little beats truncating it. Only the
                // sentences get this — an iterative scale-to-fit on a counter
                // that changes every second is layout work for nothing.
                .minimumScaleFactor(0.75)

        case .note(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(CapsuleMetrics.subdued)
                .minimumScaleFactor(0.75)

        case .joke(let reduceMotion):
            CruiseJokeView(
                reduceMotion: reduceMotion,
                tint: CapsuleMetrics.amber.opacity(0.85),
                font: .system(size: 12).italic(),
                alignment: .leading
            )
        }
    }
}
