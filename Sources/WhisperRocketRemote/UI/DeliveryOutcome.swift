import Foundation

/// Where the transcribed text actually ended up.
///
/// The clipboard always gets the text — that is a hard requirement — so the
/// only question the panel has to answer is whether it *also* got typed, and if
/// not, why. "Nothing happened and I don't know why" is the failure mode this
/// type exists to prevent.
nonisolated enum DeliveryOutcome: Equatable, Sendable {
    /// Pasted into the app that had focus when the recording started.
    case typed
    /// Clipboard only, for a reason the user can act on.
    case clipboardOnly(Reason)

    nonisolated enum Reason: Equatable, Sendable {
        /// Auto-typing is switched off in Settings. Not a problem — a choice.
        case autoPasteDisabled
        /// The Accessibility permission is missing or was revoked.
        case accessibilityDenied
        /// The frontmost app changed between the start of the recording and the
        /// paste, so typing would have landed in the wrong window.
        case focusChanged(appName: String?)

        var localizedExplanation: String {
            switch self {
            case .autoPasteDisabled:
                L.doneReasonAutoPasteOff
            case .accessibilityDenied:
                L.doneReasonAccessibility
            case .focusChanged(let appName):
                appName.map(L.doneReasonFocus(app:)) ?? L.doneReasonFocusUnknown
            }
        }
    }

    var localizedHeadline: String {
        switch self {
        case .typed: L.doneTyped
        case .clipboardOnly: L.doneClipboard
        }
    }

    /// `nil` when the text went where the user expected it to.
    var localizedExplanation: String? {
        switch self {
        case .typed: nil
        case .clipboardOnly(let reason): reason.localizedExplanation
        }
    }
}
