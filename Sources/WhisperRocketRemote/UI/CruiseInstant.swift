import Foundation

/// One instant of the cruise animation, held still.
///
/// The whole scene is a pure function of a clock (``CruiseStarField``,
/// ``CruiseRocketGeometry/flameLength(atFrame:)``) and the joke is the one thing
/// that is not, so this carries both: hand it to ``SendingStageView`` and the
/// stage stops asking the display link what time it is and draws exactly this
/// frame instead.
///
/// It exists for `--anim-probe`, which has to photograph a moving picture
/// without `screencapture` — three instants, side by side, are the only way to
/// show that the stars moved and the flame lobbed. Production never sets it.
nonisolated struct CruiseInstant: Equatable, Sendable {
    /// Seconds into the flight.
    var time: Double
    /// The joke to freeze on screen, in place of the one the rotation would
    /// have picked.
    var message: String
}
