import SwiftUI

/// The rocket, mid-flight, for as long as the host is thinking.
///
/// It replaces the old bottom-to-top launch: the rocket now points *right* and
/// holds its place while the starfield streams past behind it, which is the
/// picture the Linux app has always drawn (`popup_window._draw_processing`). A
/// launch has an end and has to loop; a cruise does not, so nothing has to be
/// hidden at a loop seam and the animation can run for as long as the upload
/// takes without ever repeating itself visibly.
///
/// The clock lives here and nowhere else. ``CruiseSceneView`` is a pure function
/// of an instant, so this view has exactly three jobs: run the clock, stop it
/// for Reduce Motion, and let a probe pin it.
struct RocketCruiseView: View {
    var reduceMotion: Bool
    /// Set only by `--anim-probe`, to photograph a chosen frame. `nil` in the app.
    var frozen: CruiseInstant?
    /// The band the scene gets. The panel's is the default; the capsule is
    /// shorter and passes its own.
    var height: Double = PanelMetrics.cruiseSceneHeight
    var rocketScaleCap: Double = PanelMetrics.cruiseRocketScale

    /// The flight's own zero. `@State`, so it is set when this view appears and
    /// the animation starts at the beginning of a send rather than partway
    /// through whatever the wall clock happened to be doing.
    @State private var epoch = Date.now

    var body: some View {
        Group {
            if let still = stillTime {
                CruiseSceneView(time: still, rocketScaleCap: rocketScaleCap)
            } else {
                // `.animation` follows the display rather than being capped to
                // upstream's 60 Hz. Capping was measured — 6.4 % of one core
                // down to 5.9 % on a 75 Hz panel — and rejected: half a point of
                // CPU is not worth 60 frames landing unevenly on 75 refreshes,
                // which is exactly the sort of judder a streaming starfield
                // shows off. Only the *flame* stays quantised to 60 Hz, because
                // there its stutter is the point.
                TimelineView(.animation) { context in
                    CruiseSceneView(
                        time: context.date.timeIntervalSince(epoch),
                        rocketScaleCap: rocketScaleCap
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    /// The instant to hold, or `nil` to let the clock run.
    ///
    /// Reduce Motion gets the same drawing with the clock stopped: the rocket,
    /// the flame and the stars are all still there, none of them moves, and the
    /// rotating joke below carries the "still working" message instead. That is
    /// the setting's actual promise — no motion, not no picture.
    private var stillTime: Double? {
        if let frozen { return frozen.time }
        // Not zero: frame zero is the flame at its shortest, which makes a
        // still look like an engine that has just cut out.
        return reduceMotion ? PanelMetrics.cruiseStillInstant : nil
    }
}
