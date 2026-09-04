import Foundation
import Observation

/// What the settings window binds to.
///
/// Everything writable is `{ get set }` so the form can use real bindings
/// instead of `Binding(get:set:)` closures; the conforming type is where a
/// change becomes a `UserDefaults` write, a Keychain write, or an
/// `SMAppService` call. The UI never learns which is which.
@MainActor
protocol SettingsModelProviding: AnyObject, Observable {
    // MARK: General

    /// Reflects `SMAppService.mainApp.status`, not a stored preference — the
    /// switch has to show what the system actually thinks. It must be backed by
    /// something *observable*: a plain computed property that asks the system on
    /// every read registers no dependency, so SwiftUI never refreshes it.
    var launchAtLogin: Bool { get set }
    /// `false` when the app is not running from `/Applications`, where
    /// `SMAppService` refuses to register it.
    var isLaunchAtLoginAvailable: Bool { get }
    /// Registered, but waiting for the user's approval in Login Items. The
    /// switch reads off in that state, which needs explaining rather than
    /// looking like a switch that would not stay on.
    var loginItemNeedsApproval: Bool { get }
    /// Re-reads the login item's status from the system. Called whenever the
    /// settings window is shown, since it can be changed in System Settings
    /// while the window is closed.
    func refreshLoginItemState()
    /// Opens System Settings › General › Login Items, for the approval case.
    func openLoginItemsSettings()

    // MARK: Audio

    /// `nil` means "follow the system default", which is a real choice and not
    /// the absence of one — it has to keep working when AirPods connect.
    var inputDeviceUID: String? { get set }
    var inputDevices: [AudioInputDevice] { get }
    /// True when a UID was saved but that device is not connected right now.
    var isSavedInputDeviceMissing: Bool { get }
    /// Enumerating devices needs no permission, so the list can be refreshed
    /// whenever the window appears.
    func refreshInputDevices()

    var soundsEnabled: Bool { get set }

    // MARK: Host

    /// Bare host or IP as typed. Validation feedback comes back through
    /// ``hostValidationMessage``.
    var host: String { get set }
    var port: Int { get set }
    /// `nil` while what is typed would make a usable endpoint.
    var hostValidationMessage: String? { get }

    /// Write-only on purpose. The token lives in the Keychain, and there is no
    /// reason for the UI to ever hold it: it can say whether one is stored and
    /// it can replace it, which is everything the settings window needs.
    var hasToken: Bool { get }
    func setToken(_ token: String) throws

    // MARK: Auto-typing

    var autoPasteEnabled: Bool { get set }
    /// Fresh `AXIsProcessTrusted()`, not a cached answer — the permission can be
    /// revoked while the app runs.
    var isAccessibilityGranted: Bool { get }
    /// Raises the system prompt (`AXIsProcessTrustedWithOptions`). Called when
    /// auto-typing is switched on without the permission, and from the
    /// explicit button.
    func requestAccessibilityPermission()
    /// Re-reads ``isAccessibilityGranted``; the window calls this when it
    /// becomes visible, since the user may have granted it in System Settings.
    func refreshAccessibilityStatus()
}
