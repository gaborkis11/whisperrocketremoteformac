import Foundation

/// The two numbers the cruise animation needs that are not the capsule's.
///
/// What is left of `PanelMetrics`. The panel it measured is gone — the
/// menu-bar item opens an `NSMenu` now — and everything the capsule draws comes
/// out of ``CapsuleMetrics/scale``; these two belong to the *drawing* rather
/// than to whatever window it happens to be in.
nonisolated enum CruiseMetrics {
    /// The most the rocket motif is ever blown up. `1` is the Linux popup's own
    /// drawing at 1:1 (`_draw_rocket`'s units), which is 50 pt nose to tail —
    /// as large as it can be before the flame runs out of room on the left.
    static let rocketScale: Double = 1

    /// The frame Reduce Motion holds. Not zero: frame zero is the flame at its
    /// shortest, and a still of that reads as an engine that has cut out.
    static let stillInstant: Double = 0.05
}
