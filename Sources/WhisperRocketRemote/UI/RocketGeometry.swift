import CoreGraphics

/// The WhisperRocket motif: a slim, upright outline rocket.
///
/// Coordinates are normalized to a 0…1 square with **y up**, so the same
/// description scales from an 18 pt menu-bar glyph to a 64 pt panel mark. Kept
/// deliberately plain — two fins, a porthole, no flames on the mark itself —
/// because at menu-bar size anything more turns to mush, and because the app
/// should read as a tool, not as a sticker.
nonisolated enum RocketGeometry {
    /// Nose cone, hull and rounded tail, as one closed contour.
    static let body: [RocketPathElement] = [
        .move(CGPoint(x: 0.50, y: 0.97)),
        // Nose: a single curve per side keeps the tip crisp at 18 px.
        .curve(to: CGPoint(x: 0.70, y: 0.50), control1: CGPoint(x: 0.63, y: 0.85), control2: CGPoint(x: 0.70, y: 0.67)),
        .line(CGPoint(x: 0.70, y: 0.24)),
        .curve(to: CGPoint(x: 0.50, y: 0.12), control1: CGPoint(x: 0.70, y: 0.17), control2: CGPoint(x: 0.62, y: 0.12)),
        .curve(to: CGPoint(x: 0.30, y: 0.24), control1: CGPoint(x: 0.38, y: 0.12), control2: CGPoint(x: 0.30, y: 0.17)),
        .line(CGPoint(x: 0.30, y: 0.50)),
        .curve(to: CGPoint(x: 0.50, y: 0.97), control1: CGPoint(x: 0.30, y: 0.67), control2: CGPoint(x: 0.37, y: 0.85)),
        .close,
    ]

    /// Swept-back fin on the right of the hull.
    static let rightFin: [RocketPathElement] = [
        .move(CGPoint(x: 0.69, y: 0.40)),
        .line(CGPoint(x: 0.94, y: 0.07)),
        .line(CGPoint(x: 0.69, y: 0.17)),
        .close,
    ]

    /// Mirror of ``rightFin``.
    static let leftFin: [RocketPathElement] = [
        .move(CGPoint(x: 0.31, y: 0.40)),
        .line(CGPoint(x: 0.06, y: 0.07)),
        .line(CGPoint(x: 0.31, y: 0.17)),
        .close,
    ]

    /// The porthole, as the bounding box of an ellipse.
    static let window = CGRect(x: 0.395, y: 0.545, width: 0.21, height: 0.21)

    /// Everything but the porthole — the parts that share one stroke.
    static let hull: [[RocketPathElement]] = [body, leftFin, rightFin]

    /// Maps a normalized, y-up point into a y-**down** drawing rect (SwiftUI,
    /// CoreGraphics contexts created unflipped-then-flipped, and so on).
    static func point(_ normalized: CGPoint, in rect: CGRect, flipped: Bool) -> CGPoint {
        CGPoint(
            x: rect.minX + normalized.x * rect.width,
            y: flipped
                ? rect.maxY - normalized.y * rect.height
                : rect.minY + normalized.y * rect.height
        )
    }

    static func rect(_ normalized: CGRect, in rect: CGRect, flipped: Bool) -> CGRect {
        let origin = point(
            CGPoint(x: normalized.minX, y: flipped ? normalized.maxY : normalized.minY),
            in: rect,
            flipped: flipped
        )
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: normalized.width * rect.width,
            height: normalized.height * rect.height
        )
    }
}
