import AppKit
import WRCore

/// The AppKit half of ``PanelPlacement``: turns a status-item button into the
/// two rectangles the geometry needs.
///
/// Both windows that hang under the menu bar — the panel and the capsule — go
/// through here, so there is exactly one place that knows a status item's frame
/// has to be converted through its own window before it means anything on
/// screen.
@MainActor
enum PanelAnchor {
    static func screenRect(of button: NSStatusBarButton?) -> CGRect? {
        guard let button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    static func visibleFrame(for button: NSStatusBarButton?) -> CGRect? {
        guard let window = button?.window else { return NSScreen.main?.visibleFrame }
        return (window.screen ?? NSScreen.main)?.visibleFrame
    }

    static func origin(below button: NSStatusBarButton?, size: CGSize) -> CGPoint {
        PanelPlacement.origin(
            below: screenRect(of: button),
            size: size,
            visibleFrame: visibleFrame(for: button)
        )
    }

    /// Whether a screen point lands on the status item. A click on the button
    /// itself is not a click "outside": letting it close a window here would
    /// make the button's own toggle reopen it a moment later.
    static func contains(_ point: NSPoint, in button: NSStatusBarButton?) -> Bool {
        screenRect(of: button)?.contains(point) ?? false
    }
}
