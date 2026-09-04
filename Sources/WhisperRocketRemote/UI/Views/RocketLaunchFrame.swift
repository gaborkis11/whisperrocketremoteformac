import Foundation

/// One frame of the launch animation, as keyframed values.
///
/// A single struct rather than three separate animators: the tracks share a
/// clock, so the fade-out cannot drift away from the top of the climb.
nonisolated struct RocketLaunchFrame: Equatable, Sendable {
    /// Points travelled upwards. Negative during the crouch.
    var rise: Double = 0
    var opacity: Double = 0
    /// 0…1, how much exhaust trails the rocket.
    var trail: Double = 0
}
