import Foundation

/// The states the UI has to look right in, each reachable from the command
/// line so they can be *seen* rather than reasoned about.
///
/// These are the capsule's real states, not a demo reel: every one of them is a
/// place a user can actually end up.
nonisolated enum UIProbeScenario: String, CaseIterable, Sendable {
    /// Microphone open, host answering. The meter is live.
    case recording
    /// Microphone open, host not answering — stored mode.
    case storedMode = "stored-mode"
    /// Recording that starts 30 s from the 5-minute ceiling, so the countdown
    /// runs, the auto-stop fires and the upload follows.
    case countdown
    /// Upload in flight: the cruise animation, running.
    case sending
    /// A second attempt in flight, so the attempt counter is on screen.
    case retry
    /// Successful dictation, pasted into the focused app.
    case done
    /// Successful dictation that stayed on the clipboard, and says why.
    case clipboardOnly = "clipboard-only"
    /// A host failure with the host's own message, and the capsule staying up.
    case failed
    /// Escape mid-recording: the capsule says so and fades, nothing is sent,
    /// the audio stays pending.
    case cancelled
    /// Idle, with a seeded ring (so the menu has a "Last record" to show).
    case idle
    /// Everything, end to end, on a loop.
    case full

    static let `default` = UIProbeScenario.full

    /// Accepts the enum's raw values plus a couple of spellings that are easier
    /// to type than to remember.
    init?(argument: String) {
        let normalized = argument.lowercased().replacing("_", with: "-")
        guard let scenario = UIProbeScenario(rawValue: normalized) else { return nil }
        self = scenario
    }

    static var allNames: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}
