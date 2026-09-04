import SwiftUI

/// The one place the phase turns into a picture.
///
/// Every stage below takes plain values, never the model: they are the parts
/// worth looking at in isolation, and a view that only knows two `Double`s
/// cannot accidentally start depending on the orchestrator.
struct PanelStageView<Model: PanelModelProviding>: View {
    var model: Model

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The transition goes on each branch, not on the `Group`: the group's
        // identity never changes, so a transition there would never fire. On a
        // branch it does, and the children's own transitions come along — which
        // is how the level meter squashes into the launch pad on its way out.
        Group {
            switch model.phase {
            case .idle:
                IdleStageView(
                    shortcutDescription: model.shortcutDescription,
                    onStart: model.toggleRecording
                )
                .transition(transition)

            case .recording:
                RecordingStageView(
                    level: model.level,
                    peak: model.peak,
                    elapsed: model.elapsed,
                    countdown: model.countdown,
                    hostReachable: model.hostReachable,
                    reduceMotion: reduceMotion,
                    onStop: model.toggleRecording
                )
                .transition(transition)

            case .sending:
                SendingStageView(
                    attempt: model.attempt,
                    maxAttempts: model.maxAttempts,
                    reduceMotion: reduceMotion
                )
                .transition(transition)

            case .done:
                // `summary` is set whenever the phase is `.done`; if it somehow
                // is not, an empty acknowledgement still beats an empty panel.
                DoneStageView(
                    summary: model.summary ?? DictationSummary(characterCount: 0, delivery: .typed),
                    reduceMotion: reduceMotion
                )
                .transition(transition)

            case .failed:
                FailedStageView(
                    problem: model.problem
                        ?? DictationProblem(
                            title: L.errorTitleGeneric,
                            detail: L.errorTransport(""),
                            isRetryable: true
                        )
                )
                .transition(transition)
            }
        }
        .frame(maxWidth: .infinity, minHeight: PanelMetrics.stageHeight)
        // Only the phase animates the swap. The level changes thirty times a
        // second and must never be mistaken for a stage change.
        .animation(PanelMetrics.phaseAnimation(reduceMotion: reduceMotion), value: model.phase)
    }

    /// Reduce Motion gets a cross-fade instead of the scale-and-slide.
    private var transition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }
}
