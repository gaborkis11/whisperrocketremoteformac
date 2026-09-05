import Foundation

/// Where a menu-bar window hangs: centred under the status item, nudged back
/// onto the screen if that would hang it off an edge.
///
/// Pure geometry, in the logic module, because two windows now need the same
/// answer (the panel and the capsule) and because the interesting cases — a
/// status item near the right edge of the screen, a window wider than the
/// screen, no status item at all — are exactly the ones that cannot be
/// reproduced by hand on a developer's Mac.
///
/// The arithmetic is spelled out from `origin` and `size` rather than using
/// `CGRect.midX` and friends: those live in CoreGraphics extensions that
/// Foundation does not re-export, and `ModuleIsolationTests` keeps this module
/// on Foundation alone.
public enum PanelPlacement {
    /// The gap between the bottom of the status item and the top of the window.
    /// 16 rather than a snug 6: Gábor wants visible air under the menu bar.
    public static let gap: Double = 16
    /// How close to the screen's edge the window may be pushed.
    public static let screenInset: Double = 8
    /// The corner an anchorless window falls back to.
    public static let orphanInset: Double = 12

    /// - Parameters:
    ///   - anchor: The status item's button, in screen coordinates. `nil` when
    ///     the status item has not been laid out yet — F0 measured that its
    ///     frame is wrong for the first ~600 ms of the process's life.
    ///   - visibleFrame: The screen the anchor is on, minus the menu bar and
    ///     the Dock.
    public static func origin(
        below anchor: CGRect?,
        size: CGSize,
        visibleFrame: CGRect?
    ) -> CGPoint {
        let visibleMinX = visibleFrame.map { $0.origin.x }
        let visibleMaxX = visibleFrame.map { $0.origin.x + $0.size.width }
        let visibleMaxY = visibleFrame.map { $0.origin.y + $0.size.height }

        guard let anchor else {
            // No anchor yet. Better a sane corner than a window at the origin
            // of the screen.
            return CGPoint(
                x: (visibleMaxX ?? 0) - size.width - orphanInset,
                y: (visibleMaxY ?? 0) - size.height - orphanInset
            )
        }

        var x = anchor.origin.x + anchor.size.width / 2 - size.width / 2
        let y = anchor.origin.y - size.height - gap

        if let visibleMinX, let visibleMaxX {
            // `min` last on purpose: a window wider than the screen is pinned
            // to the right rather than left hanging off both edges.
            x = min(max(x, visibleMinX + screenInset), visibleMaxX - size.width - screenInset)
        }
        return CGPoint(x: x, y: y)
    }
}
