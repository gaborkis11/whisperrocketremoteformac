import AppKit
import Observation
import WRCore

/// Presents ``DictationController`` (and the `Settings` object behind it) to
/// the settings window.
///
/// A wrapper for the same reason ``DictationPanelModel`` is one, and because the
/// settings form binds to things that live in three different places — user
/// defaults, the Keychain, and `SMAppService` — which the form should not have
/// to know about. Every property below is computed, so what the window shows is
/// what the system currently thinks, not a copy made when it opened.
@Observable
@MainActor
final class DictationSettingsModel: SettingsModelProviding {
    @ObservationIgnored let controller: DictationController

    /// Cached because enumerating CoreAudio devices on every `body` would be
    /// wasteful, and because the list is not observable — it changes when
    /// hardware is plugged in, not when a property is written.
    private(set) var inputDevices: [AudioInputDevice] = []

    init(controller: DictationController) {
        self.controller = controller
        inputDevices = controller.inputDevices
    }

    // MARK: - General

    /// Reads `SMAppService`'s real answer rather than the stored preference, so
    /// a login item the system turned off behind our back shows as off.
    var launchAtLogin: Bool {
        get { controller.loginItemState.isOn }
        set {
            do {
                try controller.setLaunchAtLogin(newValue)
            } catch {
                // The only realistic failure is "not in /Applications", which
                // `isLaunchAtLoginAvailable` already disables the switch for.
                // The toggle springs back to the real state on the next read,
                // which is the honest outcome; this line is for the log.
                NSLog("[wrr] launch-at-login change refused: %@", String(describing: error))
            }
        }
    }

    var isLaunchAtLoginAvailable: Bool { LoginItem.isInstalledInApplications }

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
