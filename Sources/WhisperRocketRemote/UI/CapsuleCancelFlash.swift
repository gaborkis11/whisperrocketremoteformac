import Observation

/// "The recording that just ended was thrown away, not sent."
///
/// The controller cannot say this: cancelling leaves it in `.idle`, the same
/// `.idle` a finished dictation ends in, and giving the orchestrator a phase for
/// a fade-out would be the UI leaking into the audio layer. So ``MenuBarUI``
/// raises this flag the instant Escape is pressed and lowers it when the capsule
/// has finished fading, and the capsule reads it as one more stage.
///
/// A whole object for one `Bool` because SwiftUI has to *observe* it: the
/// capsule's hosting view is built once, so a plain value passed in at
/// construction time would never change again.
///
/// Not generic, deliberately — see the note on ``MenuBarUI``.
@Observable
@MainActor
final class CapsuleCancelFlash {
    private(set) var isShowing = false

    func raise() {
        isShowing = true
    }

    func lower() {
        isShowing = false
    }
}
