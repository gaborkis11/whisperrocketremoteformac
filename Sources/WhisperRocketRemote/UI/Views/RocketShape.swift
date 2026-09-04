import SwiftUI

/// The rocket motif as a SwiftUI `Shape`, from the same ``RocketGeometry`` the
/// menu-bar image is drawn from.
///
/// The porthole is part of the path, so `fill(style: .init(eoFill: true))`
/// punches it out of a solid rocket and `stroke()` draws it as an outline —
/// one shape, both looks.
nonisolated struct RocketShape: Shape {
    func path(in rect: CGRect) -> Path {
        // The motif is drawn in a square; anything else would stretch it.
        let side = min(rect.width, rect.height)
        let box = CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )

        var path = Path()
        for contour in RocketGeometry.hull {
            append(contour, to: &path, in: box)
        }
        path.addEllipse(in: RocketGeometry.rect(RocketGeometry.window, in: box, flipped: true))
        return path
    }

    private func append(_ elements: [RocketPathElement], to path: inout Path, in box: CGRect) {
        for element in elements {
            switch element {
            case .move(let point):
                path.move(to: RocketGeometry.point(point, in: box, flipped: true))
            case .line(let point):
                path.addLine(to: RocketGeometry.point(point, in: box, flipped: true))
            case .curve(let to, let control1, let control2):
                path.addCurve(
                    to: RocketGeometry.point(to, in: box, flipped: true),
                    control1: RocketGeometry.point(control1, in: box, flipped: true),
                    control2: RocketGeometry.point(control2, in: box, flipped: true)
                )
            case .close:
                path.closeSubpath()
            }
        }
    }
}
