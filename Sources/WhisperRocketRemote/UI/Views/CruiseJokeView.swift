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
    /// The capsule is always dark and has no vibrancy behind it, so `.tertiary`
    /// there is a grey smudge; it passes its own amber instead. `nil` keeps the
    /// panel's hierarchical style.
    var tint: Color?
    var font: Font = .caption.italic()
    /// The panel centres the line under the rocket; the capsule's text column
    /// is left-aligned and the joke has to line up with the title above it.
    var alignment: Alignment = .center

    @State private var message = CruiseMessages.next()

    var body: some View {
        Text(frozenMessage ?? message)
            .font(font)
            .foregroundStyle(tint.map { AnyShapeStyle($0) }
                ?? AnyShapeStyle(HierarchicalShapeStyle.tertiary))
            .lineLimit(1)
            // Dynamic Type can take a 32-character line past 300 pt; shrinking a
            // little beats truncating a punchline.
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: alignment)
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
