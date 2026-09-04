import Foundation

/// One star, as it stands at one instant.
///
/// A plain value with no reference to anything: ``CruiseStarField`` computes
/// fifteen of these per frame on the stack, so the sixty-per-second redraw
/// allocates nothing.
nonisolated struct CruiseStar: Equatable, Sendable {
    /// Centre, in the scene's own coordinates.
    var position: CGPoint
    var radius: Double
    /// `0…1`, from the upstream `brightness = 100 + speed * 30` — the faster a
    /// star goes past, the closer it reads, so the brighter it is drawn.
    var brightness: Double
}
