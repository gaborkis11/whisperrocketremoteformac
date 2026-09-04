import SwiftUI

/// The rocket launching, for as long as the host is thinking.
///
/// It loops on a ~3.4 s cycle chosen to match the measured host round trip, so
/// a normal dictation sees roughly one launch and the restart usually lands
/// while nothing is on screen — the fade-out and the fade-in both sit at zero
/// opacity across the loop seam, which is what hides the seam.
///
/// `KeyframeAnimator` (the view, not the modifier) is what lets one clock drive
/// the climb, the fade *and* the exhaust length: the modifier form can only
/// decorate a fixed child, and the exhaust has to be rebuilt each frame.
struct RocketLaunchView: View {
    var reduceMotion: Bool

    /// How far up the rocket travels before it is gone.
    private let travel: Double = 62

    var body: some View {
        ZStack(alignment: .bottom) {
            SmokeBandView(reduceMotion: reduceMotion)

            if reduceMotion {
                // Reduce Motion: nothing flies. The rocket stays put and the
                // system's own indeterminate bar carries the "still working"
                // message instead.
                VStack(spacing: 8) {
                    RocketMarkView(style: .filled, size: PanelMetrics.launchRocketWidth)
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                }
            } else {
                KeyframeAnimator(initialValue: RocketLaunchFrame()) { frame in
                    RocketTrailView(trail: frame.trail)
                        .offset(y: -frame.rise)
                        .opacity(frame.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.rise) {
                        // A short crouch before the climb: it is what makes the
                        // launch read as a launch and not as a drift.
                        CubicKeyframe(-3, duration: 0.34)
                        CubicKeyframe(travel, duration: 2.5)
                        LinearKeyframe(travel, duration: 0.56)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1, duration: 0.22)
                        LinearKeyframe(1, duration: 2.35)
                        LinearKeyframe(0, duration: 0.43)
                        LinearKeyframe(0, duration: 0.4)
                    }
                    KeyframeTrack(\.trail) {
                        LinearKeyframe(0.25, duration: 0.34)
                        SpringKeyframe(1, duration: 0.9)
                        LinearKeyframe(1, duration: 1.6)
                        LinearKeyframe(0, duration: 0.56)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PanelMetrics.stageHeight - 22)
        .accessibilityElement()
        .accessibilityLabel(L.sendingTitle)
    }
}
