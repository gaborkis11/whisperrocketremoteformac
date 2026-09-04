import Foundation
import Observation
import WRCore

/// Everything except the token, in UserDefaults.
///
/// The properties are computed straight off `UserDefaults` rather than cached:
/// a value written by the Settings UI is then never one turn behind what the
/// controller reads. Observation is wired by hand (`access`/`withMutation`),
/// which is the documented way to make a computed property observable.
@Observable
final class Settings {
    enum Key {
        static let host = "host"
        static let port = "port"
        static let inputDeviceUID = "inputDeviceUID"
        static let autoPasteEnabled = "autoPasteEnabled"
        static let soundsEnabled = "soundsEnabled"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// The factory settings, as a registration domain.
    ///
    /// `UserDefaults.bool(forKey:)` answers `false` for a key nobody has written
    /// yet, which would silently ship the sounds switch off on a fresh install —
    /// so the wanted defaults are registered rather than left to the zero value.
    /// Registration is not a write: it only supplies the answer until the user
    /// makes a choice, and `defaults delete` still returns to it.
    ///
    /// Called from ``init`` and again from the app delegate, so the values are
    /// in place from the first line of `applicationDidFinishLaunching` even if
    /// something reads them before the `Settings` object exists.
    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.host: "",
            Key.port: HostConfig.defaultPort,
            // Sound is the only feedback a full-screen app leaves room for, so
            // it starts on; auto-paste needs an Accessibility grant, so it does not.
            Key.soundsEnabled: true,
            Key.autoPasteEnabled: false,
            Key.launchAtLoginEnabled: false,
        ])
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.registerDefaults(in: defaults)
    }

    var host: String {
        get {
            access(keyPath: \.host)
            return defaults.string(forKey: Key.host) ?? ""
        }
        set { withMutation(keyPath: \.host) { defaults.set(newValue, forKey: Key.host) } }
    }

    var port: Int {
        get {
            access(keyPath: \.port)
            let stored = defaults.integer(forKey: Key.port)
            return HostConfig.portRange.contains(stored) ? stored : HostConfig.defaultPort
        }
        set { withMutation(keyPath: \.port) { defaults.set(newValue, forKey: Key.port) } }
    }

    /// `nil` means "follow the system default input" — a different thing from
    /// pinning whatever happens to be the default today.
    var inputDeviceUID: String? {
        get {
            access(keyPath: \.inputDeviceUID)
            return defaults.string(forKey: Key.inputDeviceUID)?.nonEmpty
        }
        set {
            withMutation(keyPath: \.inputDeviceUID) {
                if let newValue, !newValue.isEmpty {
                    defaults.set(newValue, forKey: Key.inputDeviceUID)
                } else {
                    defaults.removeObject(forKey: Key.inputDeviceUID)
                }
            }
        }
    }

    var autoPasteEnabled: Bool {
        get {
            access(keyPath: \.autoPasteEnabled)
            return defaults.bool(forKey: Key.autoPasteEnabled)
        }
        set { withMutation(keyPath: \.autoPasteEnabled) { defaults.set(newValue, forKey: Key.autoPasteEnabled) } }
    }

    var soundsEnabled: Bool {
        get {
            access(keyPath: \.soundsEnabled)
            return defaults.bool(forKey: Key.soundsEnabled)
        }
        set { withMutation(keyPath: \.soundsEnabled) { defaults.set(newValue, forKey: Key.soundsEnabled) } }
    }

    /// A mirror of the real `SMAppService` status, not the truth: the system can
    /// turn a login item off behind our back, so the UI shows `LoginItem.state()`
    /// and only writes here to remember what the user asked for.
    var launchAtLoginEnabled: Bool {
        get {
            access(keyPath: \.launchAtLoginEnabled)
            return defaults.bool(forKey: Key.launchAtLoginEnabled)
        }
        set { withMutation(keyPath: \.launchAtLoginEnabled) { defaults.set(newValue, forKey: Key.launchAtLoginEnabled) } }
    }

    /// The host/port pair as WRCore validates it. Throws while the host field is
    /// still empty, which is exactly the "not configured yet" state.
    func hostConfig(token: String) throws -> HostConfig {
        try HostConfig(host: host, port: port, token: token)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
