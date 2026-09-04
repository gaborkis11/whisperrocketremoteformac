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

    /// The things the second line is ever allowed to be — including nothing at
    /// all, which is what the sending stage shows: the title says it, the
    /// rocket beside it says it again, and a line of filler under them would be
    /// the third time.
    enum Subline: Equatable {
        /// No second line; the title centres itself in the column.
        case none
        /// Seconds captured so far.
        case counter(TimeInterval)
        /// The last 30 s of the ceiling, in the counter's place.
        case countdown(Int)
        /// Something the user should know while they keep talking — stored mode.
        case warning(String)
        /// Plain supporting text: the paste hint, the failure's reassurance.
        case note(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CapsuleMetrics.textLineSpacing) {
            Text(title)
                .font(.system(
                    size: isPrimary
                        ? CapsuleMetrics.titleFontSize
                        : CapsuleMetrics.secondaryTitleFontSize,
                    weight: .semibold
                ))
                .foregroundStyle(CapsuleMetrics.ink)
                .lineLimit(1)

            if subline != .none {
                sublineView
                    .lineLimit(1)
            }
        }
        .frame(width: CapsuleMetrics.textColumnWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var sublineView: some View {
        switch subline {
        case .none:
            EmptyView()

        case .counter(let elapsed):
            Text(Duration.seconds(elapsed), format: .time(pattern: .minuteSecond))
                .font(.system(size: CapsuleMetrics.counterFontSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CapsuleMetrics.amber)

        case .countdown(let seconds):
            Text(L.capsuleCountdown(seconds))
                .font(.system(size: CapsuleMetrics.counterFontSize, weight: .semibold))
                .monospacedDigit()
                // The last five seconds go red; before that it is a heads-up,
                // not an alarm.
                .foregroundStyle(seconds <= 5 ? CapsuleMetrics.danger : CapsuleMetrics.amber)

        case .warning(let text):
            Text(text)
                .font(.system(size: CapsuleMetrics.noteFontSize, weight: .medium))
                .foregroundStyle(CapsuleMetrics.subdued)
                // A Hungarian warning is half again as long as its English
                // original; shrinking a little beats truncating it. Only the
                // sentences get this — an iterative scale-to-fit on a counter
                // that changes every second is layout work for nothing.
                .minimumScaleFactor(0.75)

        case .note(let text):
            Text(text)
                .font(.system(size: CapsuleMetrics.noteFontSize))
                .foregroundStyle(CapsuleMetrics.subdued)
                .minimumScaleFactor(0.75)
        }
    }
}
