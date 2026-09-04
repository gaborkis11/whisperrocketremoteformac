import CoreGraphics
import Foundation
import Testing
@testable import WRCore

/// Every expectation compares `Double(origin.x)`, never `origin.x` against an
/// integer literal: swift-testing's `#expect` expansion of a heterogeneous
/// `CGFloat == Int` comparison reports a failure even when the two numbers have
/// identical bit patterns (measured — `432.0 == 712 - 280` fails, `432.0 ==
/// 432.0` passes).
@Suite struct PanelPlacementTests {
    /// A 1440×900 screen with the menu bar taken off the top.
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let size = CGSize(width: 560, height: 88)

    @Test func theWindowHangsCentredUnderTheStatusItem() {
        let origin = PanelPlacement.origin(
            below: CGRect(x: 700, y: 850, width: 24, height: 24),
            size: size,
            visibleFrame: screen
        )
        #expect(Double(origin.x) == 712.0 - 280.0)
        #expect(Double(origin.y) == 850.0 - 88.0 - PanelPlacement.gap)
    }

    @Test func aStatusItemNearTheRightEdgeNudgesTheWindowBackOnScreen() {
        let origin = PanelPlacement.origin(
            below: CGRect(x: 1420, y: 850, width: 24, height: 24),
            size: size,
            visibleFrame: screen
        )
        #expect(Double(origin.x) == 1440.0 - 560.0 - PanelPlacement.screenInset)
    }

    @Test func aStatusItemNearTheLeftEdgeNudgesTheWindowBackOnScreen() {
        let origin = PanelPlacement.origin(
            below: CGRect(x: 20, y: 850, width: 24, height: 24),
            size: size,
            visibleFrame: screen
        )
        #expect(Double(origin.x) == PanelPlacement.screenInset)
    }

    /// A window wider than the screen cannot satisfy both insets; it is pinned
    /// to the right, which is the edge the status item is on.
    @Test func aWindowWiderThanTheScreenIsPinnedToTheRight() {
        let origin = PanelPlacement.origin(
            below: CGRect(x: 700, y: 850, width: 24, height: 24),
            size: CGSize(width: 2000, height: 88),
            visibleFrame: screen
        )
        #expect(Double(origin.x) == 1440.0 - 2000.0 - PanelPlacement.screenInset)
    }

    @Test func withoutAScreenTheAnchorAloneDecides() {
        let origin = PanelPlacement.origin(
            below: CGRect(x: 700, y: 850, width: 24, height: 24),
            size: size,
            visibleFrame: nil
        )
        #expect(Double(origin.x) == 712.0 - 280.0)
        #expect(Double(origin.y) == 850.0 - 88.0 - PanelPlacement.gap)
    }

    /// The status item's frame is wrong for the first ~600 ms of the process's
    /// life, so "no anchor" is a real state and not a defensive branch.
    @Test func withoutAnAnchorTheWindowGoesToTheTopRightCorner() {
        let origin = PanelPlacement.origin(below: nil, size: size, visibleFrame: screen)
        #expect(Double(origin.x) == 1440.0 - 560.0 - PanelPlacement.orphanInset)
        #expect(Double(origin.y) == 875.0 - 88.0 - PanelPlacement.orphanInset)
    }
}
