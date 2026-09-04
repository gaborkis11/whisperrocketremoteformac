import SwiftUI
import WRCore

/// The joke under the rocket, changing every two and a half seconds.
///
/// The line is English on every Mac — see ``CruiseMessages`` for why — and it is
/// deliberately hidden from VoiceOver: it says nothing about the upload that the
/// status line above it does not say properly, and a screen reader announcing a
/// fresh punchline every two and a half seconds while someone waits for their
/// text would be a small cruelty.
///
/// The rotation survives Reduce Motion: a cross-fading word is not motion, it is
/// the only sign left that anything is still happening once the stars stop.
struct CruiseJokeView: View {
    var reduceMotion: Bool
    /// Set only by `--anim-probe`, so three stills can show three different
    /// jokes and prove the pool is being drawn from. `nil` in the app.
    var frozenMessage: String?

    @State private var message = CruiseMessages.next()

    var body: some View {
        Text(frozenMessage ?? message)
            .font(.caption.italic())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            // Dynamic Type can take a 32-character line past 300 pt; shrinking a
            // little beats truncating a punchline.
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
            .accessibilityHidden(true)
            .task {
                guard frozenMessage == nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: CruiseMessages.interval)
                    guard !Task.isCancelled else { return }
                    withAnimation(
                        reduceMotion ? PanelMetrics.reducedMotionChange : PanelMetrics.jokeChange
                    ) {
                        message = CruiseMessages.next(after: message)
                    }
                }
            }
    }
}
