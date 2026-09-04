import Foundation

/// One instant of the cruise animation, held still.
///
/// The whole scene is a pure function of a clock (``CruiseStarField``,
/// ``CruiseRocketGeometry/flameLength(atFrame:)``), so an instant is all it
/// takes to ask for a named frame: hand this to ``CapsuleView`` and the lane
/// stops asking the display link what time it is and draws exactly this frame.
///
/// It exists for `--anim-probe`, which has to photograph a moving picture
/// without `screencapture` — three instants, side by side, are the only way to
/// show that the stars moved and the flame lobbed. Production never sets it.
nonisolated struct CruiseInstant: Equatable, Sendable {
    /// Seconds into the flight.
    var time: Double
}
