import SwiftUI

/// The panel while the host is working.
///
/// There is no progress to report — the host answers when it answers — so this
/// stage's job is to look like something is happening and to say, honestly,
/// which attempt this is when the first one did not take.
///
/// The layout is the Linux popup's, top to bottom: the rocket cruising through
/// its starfield, the phase in plain words under it, and the joke last, small
/// and italic. The three do different work. The picture says *wait*; the status
/// line says what is being waited for and is the only part VoiceOver reads; the
/// joke says the app is alive and has not stopped caring.
struct SendingStageView: View {
    var attempt: Int
    var maxAttempts: Int
    var reduceMotion: Bool
    /// Set only by `--anim-probe`, to hold the animation on one frame. `nil` in
    /// the app — see ``CruiseInstant``.
    var frozen: CruiseInstant?

    /// The first attempt needs no explanation; a second one does.
    private var showsAttempt: Bool { attempt > 1 && maxAttempts > 1 }

    var body: some View {
        VStack(spacing: 5) {
            RocketCruiseView(reduceMotion: reduceMotion, frozen: frozen)
                .transition(departure)

            Text(L.sendingTitle)
                .font(.callout)
                .foregroundStyle(.secondary)

            CruiseJokeView(reduceMotion: reduceMotion, frozenMessage: frozen?.message)

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

    /// How the rocket leaves when the host finally answers: forward, the way it
    /// was already pointing, while the panel cross-fades to the acknowledgement.
    /// Coming *in* it simply fades — a rocket that flew in from the left would
    /// contradict the direction of travel a second later.
    private var departure: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity,
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }
}
