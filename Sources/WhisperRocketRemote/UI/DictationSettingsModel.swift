import AppKit
import Observation
import WRCore

/// Presents ``DictationController`` (and the `Settings` object behind it) to
/// the settings window.
///
/// A wrapper for the same reason ``DictationPanelModel`` is one, and because the
/// settings form binds to things that live in three different places — user
/// defaults, the Keychain, and `SMAppService` — which the form should not have
/// to know about.
///
/// Most properties are computed straight through to their real home. The login
/// item is the exception, and deliberately so: see ``loginItemState``.
@Observable
@MainActor
final class DictationSettingsModel: SettingsModelProviding {
    @ObservationIgnored let controller: DictationController

    /// Cached because enumerating CoreAudio devices on every `body` would be
    /// wasteful, and because the list is not observable — it changes when
    /// hardware is plugged in, not when a property is written.
    private(set) var inputDevices: [AudioInputDevice] = []

    /// `SMAppService`'s answer, **stored**.
    ///
    /// This used to be a computed property reading `LoginItem.state()` on every
    /// access, which looked like the honest design and was in fact the bug:
    /// a computed property in an `@Observable` class registers no dependency,
    /// so SwiftUI had nothing to invalidate on. The switch therefore showed
    /// whatever `body` happened to read the last time something *else* forced a
    /// redraw — reliably stale by the time the window was reopened, even though
    /// the registration itself was fine (`sfltool dumpbtm` and a `--login-status`
    /// probe both said `enabled`).
    ///
    /// So: stored, hence observable; written whenever the switch is used and
    /// re-read from the system every time the window is shown, which covers the
    /// case of someone turning the login item off in System Settings.
    private(set) var loginItemState: LoginItem.State

    init(controller: DictationController) {
        self.controller = controller
        inputDevices = controller.inputDevices
        loginItemState = controller.loginItemState
    }

    // MARK: - General

    var launchAtLogin: Bool {
        get { loginItemState.isOn }
        set {
            do {
                try controller.setLaunchAtLogin(newValue)
            } catch {
                // The only realistic failure is "not in /Applications", which
                // `isLaunchAtLoginAvailable` already disables the switch for.
                NSLog("[wrr] launch-at-login change refused: %@", String(describing: error))
            }
            // Either way the switch ends up showing what the system now says,
            // not what was asked for — including `requiresApproval`, which is
            // "registered but off until you say so" rather than a silent no.
            refreshLoginItemState()
            confirmLoginItemState(matches: newValue)
        }
    }

    /// `SMAppService`'s status is served from the background task management
    /// daemon, and right after a `register()` it has occasionally not caught up
    /// by the time we read it back. One late re-read costs nothing and is only
    /// scheduled when the immediate answer disagreed with the request, so the
    /// switch cannot flicker in the normal case.
    private func confirmLoginItemState(matches requested: Bool) {
        guard loginItemState.isOn != requested, loginItemState != .requiresApproval else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.refreshLoginItemState()
        }
    }

    var isLaunchAtLoginAvailable: Bool { LoginItem.isInstalledInApplications }

    /// Registered, but macOS wants the user to confirm it in Login Items. The
    /// switch stays off in that state, so without this the window would just
    /// look broken.
    var loginItemNeedsApproval: Bool { loginItemState == .requiresApproval }

    func refreshLoginItemState() {
        loginItemState = controller.loginItemState
    }

    func openLoginItemsSettings() {
        LoginItem.openLoginItemsSettings()
    }

    // MARK: - Dictation

    var inputDeviceUID: String? {
        get { controller.settings.inputDeviceUID }
        set { controller.settings.inputDeviceUID = newValue }
    }

    var isSavedInputDeviceMissing: Bool {
        guard let uid = controller.settings.inputDeviceUID else { return false }
        return !inputDevices.contains { $0.uid == uid }
    }

    func refreshInputDevices() {
        inputDevices = controller.inputDevices
    }

    var soundsEnabled: Bool {
        get { controller.settings.soundsEnabled }
        set { controller.settings.soundsEnabled = newValue }
    }

    // MARK: - Host

    var host: String {
        get { controller.settings.host }
        set { controller.settings.host = newValue }
    }

    var port: Int {
        get { controller.settings.port }
        set { controller.settings.port = newValue }
    }

    /// The same validation the network layer will do, run as the user types.
    /// An empty host is "not filled in yet", not an error to shout about.
    var hostValidationMessage: String? {
        guard !controller.settings.host.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        do {
            _ = try controller.settings.hostConfig(token: "")
            return nil
        } catch HostConfigError.portOutOfRange {
            return L.settingsHostPortInvalid
        } catch {
            return L.settingsHostInvalid
        }
    }

    var hasToken: Bool { controller.hasToken }

    func setToken(_ token: String) throws {
        try controller.setToken(token)
    }

    // MARK: - Auto-typing

    var autoPasteEnabled: Bool {
        get { controller.settings.autoPasteEnabled }
        set { controller.settings.autoPasteEnabled = newValue }
    }

    /// Deliberately not cached: the permission can be revoked in System
    /// Settings while the app is running, and a stale "granted" would make the
    /// window lie about why nothing is being typed.
    var isAccessibilityGranted: Bool { controller.isAccessibilityTrusted }

    func requestAccessibilityPermission() {
        _ = controller.requestAccessibilityPermission()
    }

    func refreshAccessibilityStatus() {
        // Nothing to refresh — `isAccessibilityGranted` asks the system every
        // time. The method exists so the mock can pretend, and so a future
        // implementation that *does* cache has somewhere to put the reload.
    }
}
