import Foundation

/// The starfield streaming past the rocket — the whole reason the picture reads
/// as travel rather than as a rocket sitting still with its engine on.
///
/// A port of `popup_window._init_stars` / `_update_stars`, with one change of
/// method and none of behaviour. Upstream keeps a mutable list and subtracts the
/// speed from every star's `x` on each tick; here the position is *solved* for a
/// given instant instead:
///
/// ```
/// x(t) = (startX - speed · t) wrapped into the span, once per lap
/// ```
///
/// Wrapping tells us the lap number, and the lap number seeds the star's new
/// height and size — which is exactly upstream's "left the screen, so respawn on
/// the right at a random height". The difference is that this version can be
/// asked what the field looked like 1.4 seconds in, which is what the render
/// probe needs and a mutable list can never answer.
nonisolated enum CruiseStarField {
    /// Upstream draws fifteen. More would read as snow, fewer as dust.
    static let count = 15

    /// The Linux popup is 350 px wide and its speeds are in pixels per 16 ms
    /// tick. Both are scaled to whatever width this panel gives the scene, so a
    /// star takes the same *time* to cross as it does there.
    private static let referenceWidth: Double = 350

    /// Upstream lets a star live from `width + 5` down to `-5`.
    private static let margin: Double = 5

    /// Keeps the field clear of the very top and bottom edge, where a dot would
    /// look like a rendering artefact rather than a star.
    private static let verticalInset: Double = 3

    private static let radiusRange = 1.5...3.5
    /// Pixels per 16 ms tick, upstream's units.
    private static let speedRange = 2.0...5.0

    /// The star at `index`, `time` seconds into the flight.
    static func star(_ index: Int, at time: Double, in size: CGSize) -> CruiseStar {
        let span = size.width + 2 * margin
        let start = CruiseRandom.unit(index, 0) * span
        let speed = CruiseRandom.value(in: speedRange, index, 1)
        // 60 ticks a second upstream; narrower panel, proportionally slower, so
        // the crossing takes as long as it does there.
        let pointsPerSecond = speed * 60 * (size.width / referenceWidth)

        let travelled = start - pointsPerSecond * time
        let lap = Int((travelled / span).rounded(.down))
        let x = travelled - Double(lap) * span - margin

        // A fresh height and size for every lap: the star that just slid off the
        // left edge comes back somewhere else, exactly as upstream respawns it.
        let band = max(0, size.height - 2 * verticalInset)
        let y = verticalInset + CruiseRandom.unit(index, 2, lap) * band
        let radius = CruiseRandom.value(in: radiusRange, index, 3, lap)

        return CruiseStar(
            position: CGPoint(x: x, y: y),
            radius: radius,
            // Upstream: `brightness = 100 + speed * 30`, out of 255.
            brightness: (100 + speed * 30) / 255
        )
    }
}
