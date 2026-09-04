import AppKit
import SwiftUI

/// The window the panel lives in.
///
/// Not `MenuBarExtra`: it has no supported way to be opened programmatically
/// (the hotkey has to be able to open it), no control over its lifetime, and no
/// guarantee about focus. Focus is the load-bearing requirement here — the app
/// that had the caret has to keep it, or the synthetic ⌘V lands in the wrong
/// window — so this is a `.nonactivatingPanel` shown with
/// `orderFrontRegardless()`, which never activates the app.
///
/// Everything about position is event-driven. F0 measured that the status
/// item's button has a wrong frame for the first ~600 ms of the process's life,
/// so positioning at launch puts the panel in the wrong place; it is only ever
/// computed at the moment of a click or a hotkey.
@MainActor
final class PanelController {
    private let panel: NSPanel
    private let effectView: NSVisualEffectView
    private let contentView: NSView

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var autoCloseTask: Task<Void, Never>?

    /// While true, a click outside does not close the panel — something is
    /// still happening and the panel is the only place it is visible.
    var isPinnedOpen = false

    /// The status item button the panel hangs under. Weak: the status item
    /// owns it, and a click on the button itself must not be treated as a click
    /// "outside" (that would close and immediately reopen the panel).
    private weak var anchorButton: NSStatusBarButton?

    var isVisible: Bool { panel.isVisible }

    /// Where the panel is, in screen coordinates. Only the probes read this —
    /// it is what lets a screenshot be cropped to the panel instead of the
    /// whole display.
    var frameInScreen: NSRect { panel.frame }

    /// Draws the panel's own layer tree into a bitmap, for the probes.
    ///
    /// `behindWindow` vibrancy cannot be captured this way — there is nothing
    /// behind an offscreen draw — but everything the app itself renders is
    /// there, animations included, and it needs no Screen Recording permission.
    func capture() -> NSBitmapImageRep? {
        WindowCapture.image(of: effectView)
    }

    init(contentView: NSView) {
        self.contentView = contentView

        effectView = NSVisualEffectView()
        // `.hudWindow` is the material menu-bar panels use; `.active` keeps it
        // lit even though the app never becomes active.
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = PanelMetrics.cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Only take key status if something inside actually needs typing.
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.acceptsMouseMovedEvents = true

        contentView.autoresizingMask = [.width, .height]
        effectView.addSubview(contentView)
        panel.contentView = effectView
    }

    // MARK: - Showing and hiding

    func toggle(below button: NSStatusBarButton?) {
        if panel.isVisible {
            hide()
        } else {
            show(below: button)
        }
    }

    func show(below button: NSStatusBarButton?) {
        if let button { anchorButton = button }
        cancelAutoClose()
        layoutContent()
        panel.setFrameOrigin(origin(below: anchorButton, size: panel.frame.size))
        // Not `makeKeyAndOrderFront`: the focused app must keep its focus.
        panel.orderFrontRegardless()
        startMonitoringOutsideClicks()
    }

    func hide() {
        cancelAutoClose()
        stopMonitoringOutsideClicks()
        panel.orderOut(nil)
    }

    // MARK: - Size

    /// Re-measures the SwiftUI content from AppKit's side. Used for the very
    /// first layout, before SwiftUI has reported anything.
    func layoutContent(animated: Bool = false) {
        resize(to: contentView.fittingSize, animated: animated)
    }

    /// Grows or shrinks the window around the content, keeping the **top** edge
    /// pinned so the panel stays hung under the menu bar instead of drifting up
    /// and down as rows appear and disappear.
    func resize(to size: CGSize, animated: Bool) {
        let fitting = size
        guard fitting.width > 0, fitting.height > 0 else { return }

        let contentRect = NSRect(origin: .zero, size: fitting)
        let target = panel.frameRect(forContentRect: contentRect)
        guard abs(target.height - panel.frame.height) > 0.5
            || abs(target.width - panel.frame.width) > 0.5
        else { return }

        var frame = panel.frame
        frame.origin.y -= target.height - frame.height
        frame.size = target.size

        if animated, panel.isVisible, !Self.prefersReducedMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        effectView.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: frame).size)
        contentView.frame = effectView.bounds
    }

    private static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - Position

    /// Centred under the status item, nudged back onto the screen if that would
    /// hang it off an edge.
    private func origin(below button: NSStatusBarButton?, size: NSSize) -> NSPoint {
        guard let button, let window = button.window else {
            // No anchor yet (the status item has not been laid out). Better a
            // sane corner than a panel at the origin of the screen.
            let visible = NSScreen.main?.visibleFrame ?? .zero
            return NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 12)
        }

        let buttonInScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonInScreen.midX - size.width / 2
        let y = buttonInScreen.minY - size.height - 6

        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
        if let visible {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        return NSPoint(x: x, y: y)
    }

    // MARK: - Auto-close

    /// Used for the acknowledgement only: long enough to read, short enough to
    /// stay out of the way. A failure never gets one.
    func scheduleAutoClose(after delay: Duration) {
        cancelAutoClose()
        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, !isPinnedOpen else { return }
            hide()
        }
    }

    func cancelAutoClose() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
    }

    // MARK: - Outside clicks

    private func startMonitoringOutsideClicks() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Global: clicks in other apps. Mouse events need no Accessibility
        // permission (key events would).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleOutsideClick(at: NSEvent.mouseLocation)
            }
        }

        // Local: clicks in our own other windows (the settings window).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel {
                    self.handleOutsideClick(at: NSEvent.mouseLocation)
                }
            }
            return event
        }
    }

    private func stopMonitoringOutsideClicks() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleOutsideClick(at location: NSPoint) {
        guard panel.isVisible, !isPinnedOpen else { return }
        // A click on the status item is not "outside": letting it close here
        // would make the button's own toggle reopen the panel a moment later.
        if let anchorButton, let window = anchorButton.window {
            let buttonInScreen = window.convertToScreen(
                anchorButton.convert(anchorButton.bounds, to: nil)
            )
            if buttonInScreen.contains(location) { return }
        }
        hide()
    }
}
