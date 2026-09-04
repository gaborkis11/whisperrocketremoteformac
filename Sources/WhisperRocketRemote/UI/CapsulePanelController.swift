import AppKit
import SwiftUI

/// The window the capsule lives in.
///
/// The same recipe as ``PanelController`` where it matters — a
/// `.nonactivatingPanel` shown with `orderFrontRegardless()`, at
/// `.statusBar` level — because the load-bearing requirement is identical: the
/// app that had the caret has to keep it, or the synthetic ⌘V at the end of the
/// dictation lands in the wrong window.
///
/// Three things differ, and each is a simplification:
///
/// * **Fixed size.** 560×88, always. There is no content-driven resize, so none
///   of the resize machinery comes along.
/// * **No `NSVisualEffectView`.** The capsule is a solid, always-dark pill that
///   SwiftUI draws itself. Vibrancy would make it a different colour over every
///   wallpaper, which is the opposite of what a HUD wants.
/// * **It fades.** The window server derives the drop shadow from the window's
///   alpha channel, so animating `alphaValue` takes the shadow with it; the
///   shape never changes, so the shadow is computed once and stays correct.
@MainActor
final class CapsulePanelController {
    private let panel: NSPanel
    private let contentView: NSView

    private let outsideClicks = OutsideClickMonitor()
    private var autoCloseTask: Task<Void, Never>?
    /// Bumped by every `show`, so a fade that is still running cannot order out
    /// a capsule that has since been shown again.
    private var generation = 0

    /// While true, a click outside does not close the capsule — something is
    /// still happening and this is the only place it is visible.
    var isPinnedOpen = true

    private weak var anchorButton: NSStatusBarButton?

    var isVisible: Bool { panel.isVisible }
    var frameInScreen: NSRect { panel.frame }

    /// Draws the capsule's own layer tree into a bitmap, for the probes. No
    /// `screencapture`, so no Screen Recording permission.
    func capture() -> NSBitmapImageRep? {
        WindowCapture.image(of: contentView)
    }

    init(contentView: NSView) {
        self.contentView = contentView

        panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: CapsuleMetrics.width,
                height: CapsuleMetrics.height
            ),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The shape is transparent outside the pill, and the window server
        // shadows the alpha rather than the frame — so this is the capsule's
        // shadow, not a rectangle's.
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true

        contentView.frame = NSRect(
            x: 0,
            y: 0,
            width: CapsuleMetrics.width,
            height: CapsuleMetrics.height
        )
        contentView.autoresizingMask = [.width, .height]
        panel.contentView = contentView
    }

    // MARK: - Showing and hiding

    func show(below button: NSStatusBarButton?) {
        if let button { anchorButton = button }
        generation += 1
        cancelAutoClose()
        panel.setFrameOrigin(PanelAnchor.origin(below: anchorButton, size: panel.frame.size))
        // A capsule that was fading out and has been asked for again starts
        // fully opaque, not wherever the fade had got to.
        panel.alphaValue = 1
        // Not `makeKeyAndOrderFront`: the focused app must keep its focus.
        panel.orderFrontRegardless()
        outsideClicks.start(ignoring: panel) { [weak self] location in
            self?.handleOutsideClick(at: location)
        }
    }

    /// - Parameter duration: Seconds to fade over, or `nil` to go at once.
    ///   Reduce Motion always goes at once.
    func hide(fadingOver duration: Double? = nil) {
        cancelAutoClose()
        guard panel.isVisible else { return }
        guard let duration, duration > 0, !Self.prefersReducedMotion else {
            finishHiding()
            return
        }

        let generation = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.generation else { return }
                self.finishHiding()
            }
        }
    }

    private func finishHiding() {
        outsideClicks.stop()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - Auto-close

    /// Deliberately not gated on ``isPinnedOpen``: pinning is about stray
    /// *clicks*, and the acknowledgement is pinned against those while still
    /// getting out of the way on its own.
    func scheduleAutoClose(after delay: Duration, fadingOver fade: Double) {
        cancelAutoClose()
        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            hide(fadingOver: fade)
        }
    }

    func cancelAutoClose() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
    }

    // MARK: - Outside clicks

    private func handleOutsideClick(at location: NSPoint) {
        guard panel.isVisible, !isPinnedOpen else { return }
        guard !PanelAnchor.contains(location, in: anchorButton) else { return }
        hide()
    }
}
