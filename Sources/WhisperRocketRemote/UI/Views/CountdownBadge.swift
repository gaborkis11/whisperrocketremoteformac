import SwiftUI

/// The last 30 seconds of the 5-minute ceiling, counted out loud.
///
/// The auto-stop must never be silent — a recording that ends on its own with
/// no warning is indistinguishable from one that was lost. This is the visible
/// half of that promise; the stop sound is the audible half.
struct CountdownBadge: View {
    var secondsRemaining: Int

    /// The last five seconds go red; before that it is a heads-up, not an alarm.
    private var isUrgent: Bool { secondsRemaining <= 5 }

    var body: some View {
        Label {
            Text(L.countdown(secondsRemaining))
                .font(.caption)
                .monospacedDigit()
        } icon: {
            Image(systemName: "timer")
                .imageScale(.small)
        }
        .foregroundStyle(isUrgent ? .red : .secondary)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
            isUrgent ? AnyShapeStyle(.red.opacity(0.12)) : AnyShapeStyle(.quaternary),
            in: .capsule
        )
        .animation(.smooth(duration: 0.2), value: isUrgent)
        .accessibilityElement(children: .combine)
    }
}
