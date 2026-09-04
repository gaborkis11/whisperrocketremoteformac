import SwiftUI

/// The right-facing rocket, in the exact coordinates the Linux popup draws it
/// with (`popup_window._draw_rocket`).
///
/// The numbers below are upstream's *pre-scale* units: the origin is the middle
/// of the fuselage, `+x` is the direction of travel, `+y` is down. Upstream then
/// multiplies everything by `scale = 0.7`; here the caller passes whatever scale
/// the panel has room for, so the motif is the same drawing at a different size
/// rather than a redrawn approximation of it.
///
/// This is deliberately not a `Shape`: the flame changes length every frame and
/// the whole rocket bobs, so a `Canvas` draws all seven pieces from one clock in
/// one pass. A pile of `Shape`s would need the flame rebuilt anyway, and could
/// not guarantee it stayed welded to the tail.
nonisolated enum CruiseRocketGeometry {
    // MARK: - The motif's extent, in design units

    /// The nose tip, and the furthest forward anything is drawn.
    static let noseTip: Double = 30
    /// Where the fuselage ends and the flame starts.
    static let tail: Double = -20
    /// How far the fins reach above and below the centre line.
    static let finReach: Double = 22
    /// `18 + 9` from the sawtooth `+ 3` from the jitter — see ``flameLength(atFrame:)``.
    static let maxFlameLength: Double = 30

    /// Nose tip to the tip of the longest flame.
    static var width: Double { noseTip + 25 + maxFlameLength }
    /// Fin tip to fin tip.
    static var height: Double { 2 * finReach }

    // MARK: - The flame's clock

    /// Upstream: `18 + animation_frame % 10 + random(-3, 3)`, at 60 frames a
    /// second. The sawtooth is the lobbing, the jitter is the roar.
    ///
    /// The jitter is hashed from the frame number rather than drawn from
    /// `random`, so the same frame is always the same length — see
    /// ``CruiseRandom``.
    static func flameLength(atFrame frame: Int) -> Double {
        let sweep = Double(((frame % 10) + 10) % 10)
        // 0…6 → -3…3, upstream's inclusive `randint(-3, 3)`.
        let jitter = Double(Int(CruiseRandom.unit(frame, 11) * 7)) - 3
        return 18 + sweep + jitter
    }

    /// The frame number a given instant falls on. Quantising to upstream's 60 Hz
    /// keeps the flame lobbing at the same rate on a 120 Hz display.
    static func frame(at time: Double) -> Int {
        Int((time * 60).rounded(.down))
    }

    // MARK: - The pieces, back to front

    /// The outer, orange flame.
    static func outerFlame(centre: CGPoint, scale: Double, length: Double) -> Path {
        var path = Path()
        let start = point(tail, 0, centre, scale)
        path.move(to: start)
        path.addQuadCurve(
            to: point(-(25 + length), 0, centre, scale),
            control: point(-(20 + length), -8, centre, scale)
        )
        path.addQuadCurve(
            to: start,
            control: point(-(20 + length), 8, centre, scale)
        )
        path.closeSubpath()
        return path
    }

    /// The inner, yellow flame — upstream makes it 60 % of the outer one.
    static func innerFlame(centre: CGPoint, scale: Double, length: Double) -> Path {
        let inner = length * 0.6
        var path = Path()
        let start = point(tail, 0, centre, scale)
        path.move(to: start)
        path.addQuadCurve(
            to: point(-(22 + inner), 0, centre, scale),
            control: point(-(20 + inner), -4, centre, scale)
        )
        path.addQuadCurve(
            to: start,
            control: point(-(20 + inner), 4, centre, scale)
        )
        path.closeSubpath()
        return path
    }

    /// The fuselage.
    static func body(centre: CGPoint, scale: Double) -> Path {
        var path = Path()
        path.move(to: point(noseTip, 0, centre, scale))
        path.addQuadCurve(
            to: point(-5, -12, centre, scale),
            control: point(25, -12, centre, scale)
        )
        path.addLine(to: point(-20, -8, centre, scale))
        path.addLine(to: point(-20, 8, centre, scale))
        path.addLine(to: point(-5, 12, centre, scale))
        path.addQuadCurve(
            to: point(noseTip, 0, centre, scale),
            control: point(25, 12, centre, scale)
        )
        path.closeSubpath()
        return path
    }

    /// The red nose cone, drawn over the front of the fuselage.
    static func nose(centre: CGPoint, scale: Double) -> Path {
        var path = Path()
        path.move(to: point(noseTip, 0, centre, scale))
        path.addQuadCurve(
            to: point(15, -10, centre, scale),
            control: point(28, -8, centre, scale)
        )
        path.addLine(to: point(15, 10, centre, scale))
        path.addQuadCurve(
            to: point(noseTip, 0, centre, scale),
            control: point(28, 8, centre, scale)
        )
        path.closeSubpath()
        return path
    }

    /// Both red fins in one path, so they cost one fill rather than two.
    static func fins(centre: CGPoint, scale: Double) -> Path {
        var path = Path()
        for sign in [-1.0, 1.0] {
            path.move(to: point(-10, 10 * sign, centre, scale))
            path.addLine(to: point(-20, finReach * sign, centre, scale))
            path.addLine(to: point(-22, 10 * sign, centre, scale))
            path.closeSubpath()
        }
        return path
    }

    /// The blue porthole.
    static func window(centre: CGPoint, scale: Double) -> Path {
        Path(ellipseIn: circle(at: (5, 0), radius: 6, centre, scale))
    }

    /// The highlight that turns the porthole from a dot into glass.
    static func windowGlint(centre: CGPoint, scale: Double) -> Path {
        Path(ellipseIn: circle(at: (3, -2), radius: 2, centre, scale))
    }

    // MARK: - Design units → points

    private static func point(
        _ x: Double,
        _ y: Double,
        _ centre: CGPoint,
        _ scale: Double
    ) -> CGPoint {
        CGPoint(x: centre.x + x * scale, y: centre.y + y * scale)
    }

    private static func circle(
        at unit: (x: Double, y: Double),
        radius: Double,
        _ centre: CGPoint,
        _ scale: Double
    ) -> CGRect {
        let middle = point(unit.x, unit.y, centre, scale)
        let scaled = radius * scale
        return CGRect(
            x: middle.x - scaled,
            y: middle.y - scaled,
            width: scaled * 2,
            height: scaled * 2
        )
    }
}
