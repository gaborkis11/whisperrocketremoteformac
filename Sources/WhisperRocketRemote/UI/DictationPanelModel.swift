import AppKit
import KeyboardShortcuts
import Observation
import WRCore

/// Presents ``DictationController`` to the panel.
///
/// A wrapper rather than a conformance on the controller itself, for one
/// concrete reason: the controller already has a `phase` of its own type
/// (`DictationController.Phase`), and Swift cannot have two properties of the
/// same name and different types on one object. Everything else would have gone
/// straight through — the two vocabularies were designed against each other —
/// so this file is almost entirely one-line translations, and the translations
/// that are *not* one-liners are the ones worth reading: the paste outcome and
/// the failure, which is where the controller's engineering vocabulary becomes
/// something a person can act on.
///
/// Observation still works through the wrapper. Every property below reads the
/// controller inside its own getter, so a SwiftUI body that touches
/// `model.level` registers with the controller's registrar exactly as if it had
/// read `controller.level`.
@Observable
@MainActor
final class DictationPanelModel: PanelModelProviding {
    @ObservationIgnored let controller: DictationController

    init(controller: DictationController) {
        self.controller = controller
    }

    var phase: DictationPhase {
        switch controller.phase {
        case .idle: .idle
        case .recording: .recording
        case .sending: .sending
        case .done: .done
        case .failed: .failed
        }
    }

    var hostReachable: Bool? { controller.hostReachable }

    var level: Double { controller.levelMonitor.level }
    var elapsed: TimeInterval { controller.levelMonitor.elapsed }

    var countdown: Int? { controller.countdown }

    /// The controller counts from 0 while idle; the panel's contract is 1-based
    /// and only ever read during an upload.
    var attempt: Int { max(controller.attempt, 1) }
    var maxAttempts: Int { controller.maxAttempts }

    var recordings: [RecordingMeta] { controller.recordings }
    var hasFailedRecordings: Bool { controller.hasFailedRecordings }

    var summary: DictationSummary? {
        guard controller.phase == .done, let delivery = controller.lastDelivery else { return nil }
        return DictationSummary(
            characterCount: delivery.text.count,
            mode: delivery.mode,
            delivery: Self.deliveryOutcome(from: delivery.paste)
        )
    }

    var problem: DictationProblem? {
        guard controller.phase == .failed, let failure = controller.lastFailure else { return nil }
        return Self.problem(from: failure)
    }

    var failedRecordingID: UUID? {
        // `problem` already carries the phase guard and the retry verdict.
        guard let problem, problem.isRetryable else { return nil }
        return controller.lastFailure?.recordingID
    }

    func toggleRecording() {
        controller.toggle()
    }

    func resend(_ recordingID: UUID) {
        controller.resend(id: recordingID)
    }

    func cancelRecording() {
        controller.cancelRecording()
    }

    // MARK: - Translations

    /// The controller says *what happened*; the panel has to say *what it means
    /// for you*, in the language the app is running in. The controller's own
    /// `message` strings are English-only diagnostics for the probe log, so they
    /// are deliberately not reused here.
    private static func deliveryOutcome(from paste: DictationController.PasteOutcome) -> DeliveryOutcome {
        switch paste {
        case .pasted:
            .typed
        case .clipboardOnly(.disabled):
            .clipboardOnly(.autoPasteDisabled)
        case .clipboardOnly(.notTrusted):
            .clipboardOnly(.accessibilityDenied)
        case .clipboardOnly(.focusChanged(_, let actual)):
            .clipboardOnly(.focusChanged(appName: Self.applicationName(forBundleID: actual)))
        case .clipboardOnly(.postFailed):
            // The ⌘V event itself did not go out. From where the user sits that
            // is indistinguishable from a missing permission, and the fix is the
            // same: the text is on the clipboard, paste it yourself.
            .clipboardOnly(.accessibilityDenied)
        }
    }

    private static func problem(from failure: DictationController.FailureInfo) -> DictationProblem {
        switch failure.problem {
        case .upload(let kind, let serverMessage, _):
            // The full localized catalogue, including the retry verdict.
            return DictationProblem(kind: kind, serverMessage: serverMessage)

        case .noSpeech:
            return DictationProblem(
                title: L.errorTitleNoSpeech,
                detail: L.errorUnprocessable,
                isRetryable: false
            )

        case .notConfigured:
            // The controller's `detail` here is a validation diagnostic, not
            // something the host said, so it does not go in `hostMessage` — that
            // block is labelled "The host said:" and must stay true.
            return DictationProblem(
                title: L.errorTitleNotConfigured,
                detail: L.errorNotConfigured,
                isRetryable: false
            )

        case .capture(let detail):
            return DictationProblem(
                title: L.errorTitleGeneric,
                detail: L.errorCaptureFailed(detail),
                isRetryable: false
            )
        }
    }

    /// "com.apple.Safari" is not something to show a person. The bundle ID is
    /// only a fallback for an app that is no longer running by the time we look.
    private static func applicationName(forBundleID bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        return running.first?.localizedName ?? bundleID
    }
}
