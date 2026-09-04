import Foundation
import Observation
import WRCore

/// A ``SettingsModelProviding`` that keeps everything in memory.
///
/// It talks to CoreAudio for the device list — enumeration needs no permission
/// and a fake list would hide exactly the bugs a device picker has (a
/// disconnected saved device, two identically named inputs) — but the token
/// never reaches the Keychain, the login item is a `Bool`, and asking for the
/// Accessibility permission just flips a flag. Nothing here can change the real
/// system state.
@Observable
@MainActor
final class MockSettingsModel: SettingsModelProviding {
    var launchAtLogin = false
    var isLaunchAtLoginAvailable = true
    var loginItemNeedsApproval = false

    var inputDeviceUID: String?
    private(set) var inputDevices: [AudioInputDevice] = []
    var soundsEnabled = true

    var host = "100.64.0.42"
    var port = HostConfig.defaultPort

    /// In memory only. The real model writes this to the Keychain, which is
    /// precisely the thing a probe must never touch.
    private var storedToken = ""
    var hasToken: Bool { !storedToken.isEmpty }
    func setToken(_ token: String) throws { storedToken = token }

    var autoPasteEnabled = false
    private(set) var isAccessibilityGranted = false

    init() {
        refreshInputDevices()
    }

    var isSavedInputDeviceMissing: Bool {
        guard let inputDeviceUID, !inputDeviceUID.isEmpty else { return false }
        return !inputDevices.contains { $0.uid == inputDeviceUID }
    }

    /// The same validation the network layer will do, run as the user types, so
    /// a typo is caught in the field instead of at the first dictation.
    var hostValidationMessage: String? {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        do {
            _ = try HostConfig(host: host, port: port, token: storedToken)
            return nil
        } catch HostConfigError.portOutOfRange {
            return L.settingsHostPortInvalid
        } catch {
            return L.settingsHostInvalid
        }
    }

    func refreshInputDevices() {
        inputDevices = AudioDeviceList.inputDevices()
    }

    func requestAccessibilityPermission() {
        // The real model raises `AXIsProcessTrustedWithOptions`; the mock just
        // agrees, so the "permission granted" layout can be seen too.
        isAccessibilityGranted = true
    }

    func refreshAccessibilityStatus() {}

    /// In memory, like the switch itself — a probe must never re-read (or open)
    /// the real Login Items.
    func refreshLoginItemState() {}

    func openLoginItemsSettings() {}
}
