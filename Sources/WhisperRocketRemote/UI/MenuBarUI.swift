import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI

/// The whole user interface, behind one object.
///
/// The app delegate creates this and hands it the orchestrator; from there the
/// UI runs itself. It owns the status item and its menu, the capsule, and the
/// settings and About windows, and it is the only thing that watches the model
/// for the *structural* changes — the phase, the badge — that have to move
/// AppKit around.
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
    private let statusMenu: StatusMenuController
    private let capsuleController: CapsulePanelController
    private let settingsWindow: SettingsWindowController
    private let aboutWindow = AboutWindowController()

    /// Raised by Escape, lowered when the capsule has finished fading. The
    /// capsule reads it as one more stage; nothing else in the app knows a
    /// cancellation looks different from any other return to idle.
    private let cancelFlash: CapsuleCancelFlash
    private var cancelFlashTask: Task<Void, Never>?

    /// Armed only while the microphone is open — see ``EscapeCancelMonitor``.
    private let escapeMonitor = EscapeCancelMonitor()

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

        // The capsule: the live display, and the only window the hotkey opens.
        // Built here in the generic `init` because the concrete model type has
        // to reach the view while this class must not become generic.
        let cancelFlash = CapsuleCancelFlash()
        self.cancelFlash = cancelFlash
        capsuleController = CapsulePanelController(
            contentView: NSHostingView(
                rootView: CapsuleView(model: panelModel, flash: cancelFlash)
            )
        )

        // The menu is the whole click now. It is built before the status item
        // because the item wants it at birth: AppKit only tracks the click
        // itself for an item that already has a menu.
        let capsuleController = self.capsuleController
        let aboutWindow = self.aboutWindow
        statusMenu = StatusMenuController(
            model: panelModel,
            onWillOpen: { [weak capsuleController] in
                // Never both at once: the menu is what a click asks for, so the
                // capsule gets out of its way.
                capsuleController?.hide()
            },
            onSettings: { settingsWindow.show() },
            onAbout: { aboutWindow.show() }
        )
        statusItem = StatusItemController(menu: statusMenu.menu)

        applyPhase(panelModel.phase, force: true)
        startObserving()
    }

    // MARK: - Commands

    /// Only the probes open the capsule by hand; a person gets it by dictating.
    func showCapsule() {
        capsuleController.show(below: statusItem.button)
    }

    func showSettings() {
        settingsWindow.show()
    }

    /// Only the probes close it programmatically; a person uses the red button.
    func closeSettings() {
        settingsWindow.close()
    }

    /// The capsule's screen rectangle, and its live pixels, for the probes.
    ///
    /// This is an in-process draw of our own window, so unlike `screencapture`
    /// it needs no Screen Recording permission.
    var capsuleFrameInScreen: NSRect { capsuleController.frameInScreen }
    var isCapsuleVisible: Bool { capsuleController.isVisible }

    func captureCapsule() -> NSBitmapImageRep? {
        capsuleController.capture()
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

    /// Whether the Escape listener is armed right now, for the probe log. It
    /// should be true during a recording and false at every other moment.
    var isEscapeArmed: Bool { escapeMonitor.isListening }

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
            // The menu builds itself when it is asked for, so `recordings` is
            // no longer a reason to wake anything up.
            _ = panelModel.phase
            _ = panelModel.hasFailedRecordings
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
    }

    private func applyPhase(_ phase: DictationPhase, force: Bool) {
        statusItem.update(
            style: phase.wantsFilledStatusIcon ? .filled : .outline,
            showsBadge: panelModel.hasFailedRecordings
        )

        // Before the `force` guard, so the invariant holds from the first
        // moment: Escape is registered *if and only if* a recording is running.
        // A registered Carbon hotkey swallows the key system-wide, and outside a
        // recording that would break Escape everywhere else on the Mac.
        if phase == .recording {
            escapeMonitor.start { [weak self] in self?.cancel() }
        } else {
            escapeMonitor.stop()
        }

        guard !force else { return }

        applyCapsuleStage(for: phase)
    }

    // MARK: - The capsule

    private func applyCapsuleStage(for phase: DictationPhase) {
        // A new recording started inside the cancelled flash's fade — pressing
        // the hotkey again straight after Escape is a perfectly reasonable
        // thing to do, and it must not be answered with "Cancelled".
        if phase == .recording, cancelFlash.isShowing {
            cancelFlashTask?.cancel()
            cancelFlash.lower()
        }

        let stage = CapsuleStage(phase: phase, showingCancelled: cancelFlash.isShowing)
        capsuleController.isPinnedOpen = stage?.holdsOpen ?? false

        switch stage {
        case .recording:
            // Starting a recording from the hotkey has to bring *something*
            // with it — that is the feedback the whole app exists to provide.
            capsuleController.show(below: statusItem.button)

        case .sending, .failed:
            capsuleController.cancelAutoClose()
            // A resend from the menu enters `.sending` without ever passing
            // through `.recording`, and the panel that used to report it is
            // gone: without this, "Send again" would answer with nothing but a
            // filled menu-bar rocket.
            if !capsuleController.isVisible {
                capsuleController.show(below: statusItem.button)
            }

        case .done:
            capsuleController.scheduleAutoClose(
                after: CapsuleMetrics.doneDismissDelay,
                fadingOver: CapsuleMetrics.doneFade
            )

        case .cancelled:
            // The fade is already running — `cancel()` started it the moment
            // Escape was pressed.
            break

        case nil:
            capsuleController.hide()
        }
    }

    /// Escape, mid-recording: nothing is uploaded, the audio stays on disk as a
    /// pending entry, and the capsule says so on its way out.
    func cancel() {
        guard panelModel.phase == .recording else { return }
        cancelFlash.raise()
        panelModel.cancelRecording()

        capsuleController.cancelAutoClose()
        capsuleController.hide(fadingOver: CapsuleMetrics.cancelFade)

        cancelFlashTask?.cancel()
        cancelFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(CapsuleMetrics.cancelFade))
            guard let self, !Task.isCancelled else { return }
            cancelFlash.lower()
        }
    }
}
