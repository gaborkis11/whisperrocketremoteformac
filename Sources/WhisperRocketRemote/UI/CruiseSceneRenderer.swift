import SwiftUI

/// Draws the whole cruise — starfield, flame, rocket — into one `GraphicsContext`.
///
/// One pass, one clock, one view. The alternative (stars in a `Canvas`, rocket
/// as a stack of `Shape`s) would need the flame rebuilt every frame anyway, and
/// would leave the flame's position and the rocket's bob free to disagree by a
/// frame. Here they are computed from the same `time` a few lines apart and
/// cannot come apart.
///
/// Nothing here allocates beyond the handful of small `Path` values a fill
/// needs: the fifteen stars are read out of ``CruiseStarField`` as stack values,
/// there is no per-frame array, and no state is carried between frames.
nonisolated enum CruiseSceneRenderer {
    static func draw(
        _ context: inout GraphicsContext,
        size: CGSize,
        time: Double,
        scheme: ColorScheme,
        rocketScaleCap: Double = CruiseMetrics.rocketScale
    ) {
        guard size.width > 0, size.height > 0 else { return }
        drawStars(&context, size: size, time: time, scheme: scheme)
        drawRocket(&context, size: size, time: time, scheme: scheme, scaleCap: rocketScaleCap)
    }

    // MARK: - The field

    private static func drawStars(
        _ context: inout GraphicsContext,
        size: CGSize,
        time: Double,
        scheme: ColorScheme
    ) {
        for index in 0..<CruiseStarField.count {
            let star = CruiseStarField.star(index, at: time, in: size)
            let rect = CGRect(
                x: star.position.x - star.radius,
                y: star.position.y - star.radius,
                width: star.radius * 2,
                height: star.radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(CruisePalette.star(brightness: star.brightness, in: scheme))
            )
        }
    }

    // MARK: - The rocket

    private static func drawRocket(
        _ context: inout GraphicsContext,
        size: CGSize,
        time: Double,
        scheme: ColorScheme,
        scaleCap: Double
    ) {
        // Upstream parks the rocket a touch right of centre so the flame has
        // somewhere to be; `width / 2 + 15` of 350 is this fraction.
        let scale = min(
            scaleCap,
            (size.height - 6) / CruiseRocketGeometry.height
        )
        guard scale > 0 else { return }

        // A slow, shallow rise and fall: a rocket that is *going* somewhere is
        // never perfectly level, and 1.6 pt is enough to say so without turning
        // into a bounce.
        let bob = sin(time * 2.2) * 1.6
        let centre = CGPoint(
            x: size.width * 0.55,
            y: size.height / 2 + bob
        )

        let flame = CruiseRocketGeometry.flameLength(
            atFrame: CruiseRocketGeometry.frame(at: time)
        )

        // Upstream's order, which is also the only order that works: the flame
        // first so the fuselage covers where it joins, then the cone and the
        // fins over the body, then the glass.
        context.fill(
            CruiseRocketGeometry.outerFlame(centre: centre, scale: scale, length: flame),
            with: .color(CruisePalette.outerFlame)
        )
        context.fill(
            CruiseRocketGeometry.innerFlame(centre: centre, scale: scale, length: flame),
            with: .color(CruisePalette.innerFlame)
        )

        let body = CruiseRocketGeometry.body(centre: centre, scale: scale)
        context.fill(body, with: .color(CruisePalette.body))
        // The fuselage is 235-grey; on a light panel that is very nearly the
        // background, so it gets an edge. On a dark one the same line just adds
        // a little definition.
        context.stroke(
            body,
            with: .color(CruisePalette.outline(scheme)),
            lineWidth: 0.75
        )

        context.fill(
            CruiseRocketGeometry.nose(centre: centre, scale: scale),
            with: .color(CruisePalette.accent)
        )
        context.fill(
            CruiseRocketGeometry.fins(centre: centre, scale: scale),
            with: .color(CruisePalette.accent)
        )
        context.fill(
            CruiseRocketGeometry.window(centre: centre, scale: scale),
            with: .color(CruisePalette.window)
        )
        context.fill(
            CruiseRocketGeometry.windowGlint(centre: centre, scale: scale),
            with: .color(CruisePalette.windowGlint)
        )
    }
}
