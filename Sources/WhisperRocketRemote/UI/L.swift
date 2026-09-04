import Foundation

/// Every user-facing string in one place.
///
/// Two reasons this is a Swift enum in front of `Localizable.strings` rather
/// than bare `Text("some.key")` calls:
///
/// * SwiftUI's `Text(_: LocalizedStringKey)` looks in `Bundle.main`, but the
///   strings live in the SPM **resource bundle**. Every lookup has to name that
///   bundle explicitly, and doing it once here is the only way it stays true.
/// * A typo in a key is otherwise invisible until the key itself shows up in
///   the panel. Here it is a compile error.
///
/// The keys are also what ``UIProbes`` audits: it parses both `.lproj` files
/// and checks that neither language is missing one.
nonisolated enum L {
    // MARK: - Bundle

    /// The SwiftPM **resource** bundle, not `Bundle.main`. `.process("Resources")`
    /// flattens subdirectories (F0 measured that: `Sounds/` disappeared) but
    /// keeps `.lproj` directories, because SwiftPM treats those as
    /// localizations rather than as folders — proven at runtime by
    /// `UIProbes --l10n-probe`.
    static var bundle: Bundle { .module }

    private static func t(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func t(_ key: String, _ arguments: any CVarArg...) -> String {
        // Positional `%1$@`-style substitution is the whole point of a .strings
        // file: a translator has to be able to reorder the arguments. Passing
        // `locale:` is what makes the numbers themselves locale-correct.
        String(format: t(key), locale: .current, arguments: arguments)
    }

    // MARK: - Status item

    static var statusItemAccessibility: String { t("statusItem.accessibility") }
    static var statusItemAccessibilityFailed: String { t("statusItem.accessibility.failed") }

    // MARK: - Panel chrome

    static var appName: String { t("app.name") }
    static var statusIdle: String { t("status.idle") }
    static var statusRecording: String { t("status.recording") }
    static var statusSending: String { t("status.sending") }
    static var statusDone: String { t("status.done") }
    static var statusFailed: String { t("status.failed") }

    // MARK: - Idle

    static func idleHint(shortcut: String) -> String { t("idle.hint.shortcut", shortcut) }
    static var idleHintNoShortcut: String { t("idle.hint.noShortcut") }
    static var startRecording: String { t("action.startRecording") }
    static var stopRecording: String { t("action.stopRecording") }

    // MARK: - Recording

    static var recordingHint: String { t("recording.hint") }
    static var storedModeTitle: String { t("storedMode.title") }
    static var storedModeDetail: String { t("storedMode.detail") }
    static func countdown(_ seconds: Int) -> String { t("countdown.autoStop", seconds) }

    // MARK: - Sending

    static var sendingTitle: String { t("sending.title") }
    static func sendingAttempt(_ attempt: Int, of total: Int) -> String {
        t("sending.attempt", attempt, total)
    }

    // MARK: - Done

    static var doneTyped: String { t("done.typed") }
    static var doneClipboard: String { t("done.clipboard") }
    static var doneComposed: String { t("done.composed") }
    static func doneCharacters(_ count: Int) -> String { t("done.characters", count) }
    static var doneReasonAutoPasteOff: String { t("done.reason.autoPasteOff") }
    static var doneReasonAccessibility: String { t("done.reason.accessibility") }
    static func doneReasonFocus(app: String) -> String { t("done.reason.focus", app) }
    static var doneReasonFocusUnknown: String { t("done.reason.focus.unknown") }

    // MARK: - Failure

    static var failureHostSaid: String { t("failed.hostSaid") }
    static var failureKept: String { t("failed.kept") }

    static var errorTitleGeneric: String { t("error.title.generic") }
    static var errorTitleToken: String { t("error.title.token") }
    static var errorTitleNoSpeech: String { t("error.title.noSpeech") }
    static var errorTitleUnreachable: String { t("error.title.unreachable") }
    static var errorTitleTooLarge: String { t("error.title.tooLarge") }
    static var errorTitleBusy: String { t("error.title.busy") }
    static var errorTitleLoading: String { t("error.title.loading") }
    static var errorTitleNotConfigured: String { t("error.title.notConfigured") }

    static var errorBadRequest: String { t("error.detail.badRequest") }
    static var errorUnauthorized: String { t("error.detail.unauthorized") }
    static var errorNotFound: String { t("error.detail.notFound") }
    static var errorPayloadTooLarge: String { t("error.detail.payloadTooLarge") }
    static var errorUnprocessable: String { t("error.detail.unprocessable") }
    static var errorRateLimited: String { t("error.detail.rateLimited") }
    static var errorServerError: String { t("error.detail.serverError") }
    static var errorServiceUnavailable: String { t("error.detail.serviceUnavailable") }
    static func errorUnexpectedStatus(_ status: Int) -> String { t("error.detail.unexpectedStatus", status) }
    static var errorTimedOut: String { t("error.detail.timedOut") }
    static var errorCannotConnect: String { t("error.detail.cannotConnect") }
    static var errorCancelled: String { t("error.detail.cancelled") }
    static func errorAudioUnreadable(_ message: String) -> String { t("error.detail.audioUnreadable", message) }
    static func errorTransport(_ message: String) -> String { t("error.detail.transport", message) }
    static var errorNotConfigured: String { t("error.detail.notConfigured") }
    static func errorCaptureFailed(_ detail: String) -> String { t("error.detail.captureFailed", detail) }

    // MARK: - Recording list

    static var recordingsTitle: String { t("recordings.title") }
    static var recordingStatusPending: String { t("recording.status.pending") }
    static var recordingStatusSending: String { t("recording.status.sending") }
    static var recordingStatusSent: String { t("recording.status.sent") }
    static var recordingStatusFailed: String { t("recording.status.failed") }
    static var recordingResend: String { t("recording.resend") }
    static func recordingAttempt(_ attempt: Int, of total: Int) -> String {
        t("recording.attempt", attempt, total)
    }

    // MARK: - Footer

    static var actionSettings: String { t("action.settings") }
    static var actionQuit: String { t("action.quit") }

    // MARK: - Settings

    static var settingsWindowTitle: String { t("settings.window.title") }
    static var settingsSectionGeneral: String { t("settings.section.general") }
    static var settingsSectionDictation: String { t("settings.section.dictation") }
    static var settingsSectionHost: String { t("settings.section.host") }
    static var settingsLaunchAtLogin: String { t("settings.launchAtLogin") }
    static var settingsLaunchAtLoginUnavailable: String { t("settings.launchAtLogin.unavailable") }
    static var settingsHotkey: String { t("settings.hotkey") }
    static var settingsHotkeyNeedsCommand: String { t("settings.hotkey.needsCommand") }
    static var settingsMicrophone: String { t("settings.microphone") }
    static var settingsMicrophoneSystemDefault: String { t("settings.microphone.systemDefault") }
    static var settingsMicrophoneMissing: String { t("settings.microphone.missing") }
    static var settingsHostAddress: String { t("settings.host.address") }
    static var settingsHostPort: String { t("settings.host.port") }
    static var settingsHostToken: String { t("settings.host.token") }
    static var settingsHostTokenHint: String { t("settings.host.token.hint") }
    static var settingsHostTokenStored: String { t("settings.host.token.stored") }
    static var settingsHostTokenEmpty: String { t("settings.host.token.empty") }
    static func settingsHostTokenFailed(_ reason: String) -> String {
        t("settings.host.token.failed", reason)
    }
    static var settingsHostInvalid: String { t("settings.host.invalid") }
    static var settingsHostPortInvalid: String { t("settings.host.portInvalid") }
    static var settingsAutoPaste: String { t("settings.autoPaste") }
    static var settingsAutoPasteHint: String { t("settings.autoPaste.hint") }
    static var settingsAutoPasteNeedsPermission: String { t("settings.autoPaste.needsPermission") }
    static var settingsAutoPasteGrant: String { t("settings.autoPaste.grant") }
    static var settingsSounds: String { t("settings.sounds") }
}
