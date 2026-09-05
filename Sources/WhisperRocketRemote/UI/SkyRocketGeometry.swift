import CoreGraphics

/// The app icon's rocket, as one flat silhouette for the menu bar.
///
/// Same drawing and the same numbers as `scripts/make-appicon.swift`: the mark
/// in the Dock and the glyph in the menu bar are one rocket, which is the point
/// of drawing both from a description instead of shipping two bitmaps that
/// drift apart. The coordinates are the artwork's own — x 0…100, y 0…150, **y
/// down** — so a change to the icon can be copied across without re-deriving
/// anything.
///
/// The menu bar gets the *silhouette*: hull, fins and nozzle unioned into a
/// single shape with the porthole punched out of it, and no flame. At 18 points
/// a flame is three grey pixels under the tail, and the porthole has to be a
/// hole rather than a second colour because a template image has no colours —
/// only opacity — for AppKit to tint.
nonisolated enum SkyRocketGeometry {
    /// The box the artwork is authored in.
    static let viewBox = CGRect(x: 0, y: 0, width: 100, height: 150)

    // MARK: - The parts, in viewBox coordinates

    /// Nose, body and the flat tail the nozzle hangs off.
    static func hull(_ t: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 50, y: 10), transform: t)
        path.addCurve(to: CGPoint(x: 73, y: 74), control1: CGPoint(x: 66, y: 26), control2: CGPoint(x: 73, y: 50), transform: t)
        path.addCurve(to: CGPoint(x: 66, y: 106), control1: CGPoint(x: 73, y: 88), control2: CGPoint(x: 70, y: 99), transform: t)
        path.addLine(to: CGPoint(x: 34, y: 106), transform: t)
        path.addCurve(to: CGPoint(x: 27, y: 74), control1: CGPoint(x: 30, y: 99), control2: CGPoint(x: 27, y: 88), transform: t)
        path.addCurve(to: CGPoint(x: 50, y: 10), control1: CGPoint(x: 27, y: 50), control2: CGPoint(x: 34, y: 26), transform: t)
        path.closeSubpath()
        return path
    }

    static func leftFin(_ t: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 30, y: 84), transform: t)
        path.addCurve(to: CGPoint(x: 14, y: 114), control1: CGPoint(x: 20, y: 92), control2: CGPoint(x: 15, y: 103), transform: t)
        path.addCurve(to: CGPoint(x: 33, y: 106), control1: CGPoint(x: 20, y: 110), control2: CGPoint(x: 27, y: 107), transform: t)
        path.closeSubpath()
        return path
    }

    /// ``leftFin`` mirrored across the hull.
    static func rightFin(_ t: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 70, y: 84), transform: t)
        path.addCurve(to: CGPoint(x: 86, y: 114), control1: CGPoint(x: 80, y: 92), control2: CGPoint(x: 85, y: 103), transform: t)
        path.addCurve(to: CGPoint(x: 67, y: 106), control1: CGPoint(x: 80, y: 110), control2: CGPoint(x: 73, y: 107), transform: t)
        path.closeSubpath()
        return path
    }

    static func nozzle(_ t: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 42, y: 106), transform: t)
        path.addLine(to: CGPoint(x: 58, y: 106), transform: t)
        path.addLine(to: CGPoint(x: 55, y: 116), transform: t)
        path.addLine(to: CGPoint(x: 45, y: 116), transform: t)
        path.closeSubpath()
        return path
    }

    /// The porthole, filled in the icon and punched out in the glyph.
    static func porthole(_ t: CGAffineTransform) -> CGPath {
        CGPath(ellipseIn: CGRect(x: 38, y: 50, width: 24, height: 24), transform: [t])
    }

    // MARK: - The glyph

    /// What the whole rocket covers, without the flame: the box the silhouette
    /// is fitted into. Measured from the paths above, not guessed.
    static let silhouetteBounds = CGRect(x: 14, y: 10, width: 72, height: 106)

    /// Hull ∪ fins ∪ nozzle, porthole subtracted, fitted into `rect` and
    /// flipped into a y-**up** context (which is what AppKit hands us).
    ///
    /// The union is not decoration: the fins are authored in the opposite
    /// winding direction to the hull, so simply appending the subpaths and
    /// filling would punch a notch out of the rocket wherever a fin overlaps
    /// the body. Core Graphics' boolean ops settle it exactly once, here.
    static func silhouette(in rect: CGRect) -> CGPath {
        let t = transform(fitting: rect)
        let solid = hull(t)
            .union(leftFin(t))
            .union(rightFin(t))
            .union(nozzle(t))
        return solid.subtracting(porthole(t))
    }

    /// Maps ``silhouetteBounds`` into `rect`: aspect kept, centred, y flipped.
    static func transform(fitting rect: CGRect) -> CGAffineTransform {
        let bounds = silhouetteBounds
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        return CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
    }
}
