import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI

/// The whole user interface, behind one object.
///
/// The app delegate creates this and hands it the orchestrator; from there the
/// UI runs itself. It owns the status item, the panel and the settings window,
/// and it is the only thing that watches the model for the *structural*
/// changes — the phase, the badge, the list — that have to move AppKit around.
///
/// It deliberately does **not** watch the level or the elapsed time. Those
/// change thirty times a second, and SwiftUI already redraws the meter from
/// them; waking this observer that often would mean re-measuring and resizing
/// the window thirty times a second for no reason.
///
/// **The class is not generic, and must not become generic.** Swift 6.3.3's
/// optimiser segfaults in `EarlyPerfInliner` on the implicit `deinit` of a
/// generic class here — a debug build is fine, a release build crashes the
/// compiler. The models arrive through a generic `init` (a function, which is
/// not affected) and are stored as existentials; the SwiftUI views stay generic
/// over their concrete model type, which is what keeps observation tracking
/// exact.
@MainActor
final class MenuBarUI {
    /// Existential on purpose — see the note above. Observation tracking works
    /// through it: the property access still runs the `@Observable` getter.
    private let panelModel: any PanelModelProviding
    private let statusItem: StatusItemController
    private let panelController: PanelController
    private let settingsWindow: SettingsWindowController

    /// Re-armed after every notification: `withObservationTracking` fires once.
    private var observationTask: Task<Void, Never>?
    private var lastPhase: DictationPhase

    init<PanelModel: PanelModelProviding, SettingsModel: SettingsModelProviding>(
        panelModel: PanelModel,
        settingsModel: SettingsModel,
        shortcutName: KeyboardShortcuts.Name
    ) {
        self.panelModel = panelModel
        lastPhase = panelModel.phase

        // The concrete type is captured in the closures rather than stored, so
        // the window controller needs no type parameter of its own.
        let settingsWindow = SettingsWindowController(
            onShow: { [weak settingsModel] in
                // The window is reused, so the view's `.task` runs only once —
                // without this the login-item switch would keep showing what
                // the system said when the window first opened.
                settingsModel?.refreshLoginItemState()
                settingsModel?.refreshInputDevices()
                settingsModel?.refreshAccessibilityStatus()
            }
        ) {
            let hosting = NSHostingView(
                rootView: SettingsView(model: settingsModel, shortcutName: shortcutName)
            )
            hosting.sizingOptions = [.minSize, .intrinsicContentSize]
            return hosting
        }
        self.settingsWindow = settingsWindow

        // A box, because the panel controller and the view that resizes it have
        // to be built in the same breath and each needs the other.
        let controllerBox = PanelControllerBox()
        let hosting = NSHostingView(
            rootView: PanelView(
                model: panelModel,
                onSettings: { settingsWindow.show() },
                onQuit: { NSApp.terminate(nil) },
                onContentSize: { size in
                    controllerBox.controller?.resize(to: size, animated: true)
                }
            )
        )
        hosting.sizingOptions = [.minSize, .intrinsicContentSize]
        panelController = PanelController(contentView: hosting)
        controllerBox.controller = panelController

        // The status item hands its own button to the callback, so the panel
        // can be positioned under it without this object having to exist yet.
        let panelController = self.panelController
        statusItem = StatusItemController { [weak panelController] button in
            panelController?.toggle(below: button)
        }

        applyPhase(panelModel.phase, force: true)
        startObserving()
    }

    // MARK: - Commands

    func showPanel() {
        panelController.show(below: statusItem.button)
    }

    func showSettings() {
        settingsWindow.show()
    }

    /// Only the probes close it programmatically; a person uses the red button.
    func closeSettings() {
        settingsWindow.close()
    }

    /// The panel's screen rectangle, for the probes' screenshots.
    var panelFrameInScreen: NSRect { panelController.frameInScreen }

    /// Draws the *live* panel — vibrancy aside, exactly what is on screen,
    /// mid-animation — into a bitmap, for the probes.
    ///
    /// This is an in-process draw of our own window, so unlike `screencapture`
    /// it needs no Screen Recording permission.
    func capturePanel() -> NSBitmapImageRep? {
        panelController.capture()
    }

    func captureSettings() -> NSBitmapImageRep? {
        settingsWindow.capture()
    }

    /// The menu-bar image the status item is showing *right now*, magnified so
    /// an 18-point glyph can actually be looked at. The one thing a probe cannot
    /// do is photograph the menu bar, so it asks the button what it is wearing.
    func captureStatusItemIcon(scale: Int = 8) -> NSBitmapImageRep? {
        guard let image = statusItem.button?.image else { return nil }
        // The backdrop has to match the menu bar the icon was resolved for, or
        // the preview lies: a badged image bakes in the menu bar's ink, so a
        // dark-mode icon on a light preview looks broken when it is correct.
        let isDark = statusItem.isMenuBarDark
        return StatusItemIcon.magnified(
            image,
            scale: scale,
            // A template image is painted by AppKit in the menu bar's ink; a
            // badged one already carries its own colours.
            tint: image.isTemplate ? (isDark ? .white : .black) : nil,
            background: isDark
                ? NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)
                : NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
        )
    }

    /// What the status item is showing, in words, for the probe log.
    var statusItemDescription: String {
        "style=\(statusItem.style) badged=\(statusItem.showsBadge) "
            + "template=\(statusItem.button?.image?.isTemplate ?? false) "
            + "menuBar=\(statusItem.isMenuBarDark ? "dark" : "light")"
    }

    // MARK: - Observation

    private func startObserving() {
        withObservationTracking {
            // Exactly the properties that move AppKit. Anything read here wakes
            // this observer, so the meter's `level` must stay out of it.
            _ = panelModel.phase
            _ = panelModel.hasFailedRecordings
            _ = panelModel.recordings
            _ = panelModel.summary
            _ = panelModel.problem
        } onChange: { [weak self] in
            // `onChange` runs *before* the value is written, so the new state is
            // only readable after a hop.
            Task { @MainActor [weak self] in
                guard let self else { return }
                modelDidChange()
                startObserving()
            }
        }
    }

    private func modelDidChange() {
        let phase = panelModel.phase
        if phase != lastPhase {
            applyPhase(phase, force: false)
            lastPhase = phase
        } else {
            statusItem.update(
                style: phase.wantsFilledStatusIcon ? .filled : .outline,
                showsBadge: panelModel.hasFailedRecordings
            )
        }
        // The window follows the content by itself: `PanelView` reports its own
        // settled size, which is the only measurement that is not racing
        // SwiftUI's update.
    }

    private func applyPhase(_ phase: DictationPhase, force: Bool) {
        statusItem.update(
            style: phase.wantsFilledStatusIcon ? .filled : .outline,
            showsBadge: panelModel.hasFailedRecordings
        )

        // A stray click must not close the panel out from under something that
        // is still running.
        panelController.isPinnedOpen = phase.holdsPanelOpen

        guard !force else { return }

        // Starting a recording from the hotkey has to bring the panel with it —
        // that is the feedback the whole app exists to provide.
        if phase == .recording, !panelController.isVisible {
            panelController.show(below: statusItem.button)
        }

        if phase.dismissesItself {
            panelController.scheduleAutoClose(after: PanelMetrics.doneDismissDelay)
        } else {
            panelController.cancelAutoClose()
        }
    }
}
