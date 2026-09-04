import SwiftUI

/// The cruise animation's colours — the one place in this UI that names its own
/// rather than asking for a semantic style.
///
/// Everything else in the panel uses `.primary` / `.secondary` / `.tint` so
/// vibrancy and the appearance switch keep working for free. This is the
/// exception on purpose: the rocket is a flat-design *illustration* lifted from
/// the Linux popup, and a red nose cone that turns grey in dark mode would not
/// be the same drawing. The literal sRGB values below are `_draw_rocket`'s.
///
/// The two things that *do* follow the appearance are the ones that would
/// otherwise disappear: the stars (white on a dark panel, dark on a light one)
/// and the hairline that keeps the near-white fuselage off a near-white
/// background.
nonisolated enum CruisePalette {
    /// `QColor(235, 235, 240)` — the fuselage.
    static let body = Color(.sRGB, red: 235 / 255, green: 235 / 255, blue: 240 / 255)
    /// `QColor(240, 90, 90)` — the nose cone and both fins.
    static let accent = Color(.sRGB, red: 240 / 255, green: 90 / 255, blue: 90 / 255)
    /// `QColor(100, 180, 255)` — the porthole.
    static let window = Color(.sRGB, red: 100 / 255, green: 180 / 255, blue: 255 / 255)
    /// `QColor(200, 230, 255)` — the glint on the glass.
    static let windowGlint = Color(.sRGB, red: 200 / 255, green: 230 / 255, blue: 255 / 255)
    /// `QColor(255, 140, 0, 200)` — the outer flame.
    static let outerFlame = Color(.sRGB, red: 1, green: 140 / 255, blue: 0).opacity(200 / 255)
    /// `QColor(255, 255, 100, 230)` — the inner flame.
    static let innerFlame = Color(.sRGB, red: 1, green: 1, blue: 100 / 255).opacity(230 / 255)

    /// A hairline around the fuselage. Barely there on a dark panel, and the
    /// only thing separating a 235-grey rocket from a light one.
    static func outline(_ scheme: ColorScheme) -> Color {
        Color(.sRGB, white: 0, opacity: scheme == .light ? 0.20 : 0.10)
    }

    /// One star, given its `0…1` brightness.
    ///
    /// On a dark panel this is upstream's own greyscale ramp (`0.63…0.98` white
    /// at `200/255` alpha). On a light one the ramp is inverted — the brightest
    /// star becomes the *darkest* speck — because the brightness is really about
    /// contrast against the background, and white has none against white. The
    /// range is kept off pure black so the field still reads as dust rather than
    /// as pepper.
    static func star(brightness: Double, in scheme: ColorScheme) -> Color {
        if scheme == .light {
            // brightness 0.63…0.98 → white 0.47…0.17.
            Color(.sRGB, white: 1 - 0.85 * brightness, opacity: 0.6)
        } else {
            Color(.sRGB, white: brightness, opacity: 200 / 255)
        }
    }
}
