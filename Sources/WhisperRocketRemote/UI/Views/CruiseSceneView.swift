import SwiftUI

/// One frame of the cruise, drawn.
///
/// A `Canvas` rather than a stack of shapes: fifteen stars, two flames and five
/// rocket pieces is nineteen views to diff sixty times a second, against one
/// immediate-mode draw that diffs nothing. It takes the instant as a parameter
/// and holds no clock of its own, which is what lets ``RocketCruiseView`` decide
/// whether that clock is running.
struct CruiseSceneView: View {
    /// Seconds into the flight.
    var time: Double
    /// The most the rocket motif may be blown up. The default is the panel's;
    /// the capsule's shorter band would otherwise let the rocket grow into it.
    var rocketScaleCap: Double = PanelMetrics.cruiseRocketScale

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            CruiseSceneRenderer.draw(
                &context,
                size: size,
                time: time,
                scheme: colorScheme,
                rocketScaleCap: rocketScaleCap
            )
        }
        // The picture says nothing VoiceOver can use that the status line below
        // it does not already say better.
        .accessibilityHidden(true)
    }
}
