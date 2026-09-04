import SwiftUI

/// What is left of the level meter once the recording stops: the bars squash
/// down into this band as they leave, and the rocket lifts off from it.
///
/// It is one wide, soft, blurred capsule rather than nine little ones — smoke
/// has no bars in it — and it fades in with the sending stage, so the handover
/// from meter to launch pad reads as one movement.
struct SmokeBandView: View {
    var reduceMotion: Bool

    @State private var settled = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.secondary.opacity(0.18), .secondary.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(
                width: settled ? 108 : 72,
                height: settled ? 10 : 4
            )
            .blur(radius: 6)
            .opacity(settled ? 1 : 0)
            .animation(
                reduceMotion
                    ? PanelMetrics.reducedMotionChange
                    : .smooth(duration: 0.7),
                value: settled
            )
            .onAppear { settled = true }
            .accessibilityHidden(true)
    }
}
