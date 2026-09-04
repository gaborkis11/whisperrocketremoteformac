import CoreGraphics

/// One drawing command of the rocket motif, in a normalized 0…1 square with
/// **y pointing up**.
///
/// The motif is described once, as data, because it has to be drawn by two very
/// different renderers: `NSBezierPath` for the menu-bar image (there is no
/// "rocket" SF Symbol, so the icon is drawn in code) and SwiftUI's `Path` for
/// the panel. Anything else drifts — a rocket in the menu bar that is not the
/// rocket in the panel.
nonisolated enum RocketPathElement: Equatable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    case close
}
