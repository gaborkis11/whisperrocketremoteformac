import Foundation
import ServiceManagement

/// "Start at login", via `SMAppService.mainApp`.
///
/// The service registers the bundle *at its current path*, so an app run from
/// `~/Downloads` or from a build directory would register a path that moves.
/// That is refused here rather than registered and silently broken later.
enum LoginItem {
    enum State: Equatable, Sendable {
        case enabled
        case disabled
        /// Registered, but the user has to approve it in Login Items.
        case requiresApproval
        /// Registered against a bundle macOS can no longer find.
        case notFound
        /// Not runnable as a login item from where this copy lives.
        case unavailable(reason: String)

        var isOn: Bool { self == .enabled }
    }

    static let requiredPrefix = "/Applications/"

    static var bundlePath: String { Bundle.main.bundlePath }

    /// `SMAppService` keys the registration to the bundle path, and TCC keys the
    /// microphone grant to it too — `/Applications` is the one location that
    /// stays put.
    static var isInstalledInApplications: Bool {
        bundlePath.hasPrefix(requiredPrefix)
    }

    static func state() -> State {
        guard isInstalledInApplications else {
            return .unavailable(reason: "Move the app to /Applications to start it at login (currently at \(bundlePath)).")
        }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .disabled
        }
    }

    enum LoginItemError: Error, Sendable {
        case notInApplications(String)
        case underlying(String)

        var message: String {
            switch self {
            case .notInApplications(let path):
                "Start at login needs the app in /Applications; it is running from \(path)."
            case .underlying(let text):
                text
            }
        }
    }

    static func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        guard isInstalledInApplications else { throw .notInApplications(bundlePath) }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw .underlying(error.localizedDescription)
        }
    }

    /// Opens the Login Items pane, for the `requiresApproval` case.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
