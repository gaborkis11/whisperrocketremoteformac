import Foundation
import Observation
import WRCore

/// Everything the capsule and the status item's menu read, and the three
/// things they can ask for.
///
/// This is the F4↔F3 contract. `DictationController` conforms to it; the UI
/// never sees the controller's own type, and the UI was built and exercised
/// against ``MockPanelModel`` before the controller existed.
///
/// `Observable` is a refinement rather than a nicety: SwiftUI's observation
/// tracking is what redraws the capsule, and requiring it here means a
/// conforming type that forgot `@Observable` fails to compile instead of
/// quietly freezing the meter.
@MainActor
protocol PanelModelProviding: AnyObject, Observable {
    /// What the panel is showing. Every visual stage derives from this alone.
    var phase: DictationPhase { get }

    /// `nil` until the health probe answers — which is the normal state for the
    /// first moment of every recording, because the probe runs *alongside* the
    /// capture instead of gating it. `false` is what raises the stored-mode
    /// banner.
    var hostReachable: Bool? { get }

    /// Smoothed 0…1 microphone level, straight from `AudioLevelMonitor`.
    var level: Double { get }
    /// Seconds captured so far, from the sample-accurate frame count.
    var elapsed: TimeInterval { get }

    /// Whole seconds until the 5-minute auto-stop, or `nil` outside the last
    /// 30 s. Straight from `RecordingLimits.countdown(frameCount:sampleRate:)`.
    var countdown: Int? { get }

    /// 1-based attempt number of the upload in flight.
    var attempt: Int { get }
    /// Usually `UploadPlan.maxAttempts`.
    var maxAttempts: Int { get }

    /// The ring, **newest first**. The ring holds one entry now, so `first` is
    /// the menu's "Last record".
    var recordings: [RecordingMeta] { get }
    /// Drives the red dot on the menu-bar icon.
    var hasFailedRecordings: Bool { get }

    /// Set while ``phase`` is `.done`.
    var summary: DictationSummary? { get }
    /// Set while ``phase`` is `.failed`.
    var problem: DictationProblem? { get }

    /// What the capsule's retry button would re-send, or `nil` when there is
    /// nothing worth re-sending — which is what hides the button. "Nothing
    /// worth" is the failure's own verdict: a 401 or a recording with no speech
    /// in it would fail again the same way, and offering a button that cannot
    /// work is worse than offering none.
    var failedRecordingID: UUID? { get }

    /// Start or stop a recording — the same thing the hotkey does.
    func toggleRecording()
    /// Re-upload a `pending` or `failed` entry.
    func resend(_ recordingID: UUID)
    /// Abandon the recording in progress: nothing is uploaded, and the audio
    /// stays on disk as a `pending` entry the user can send later. This is what
    /// Escape does, and it is deliberately *not* `toggleRecording()` — the two
    /// differ in exactly the thing that matters, whether anything is sent.
    func cancelRecording()
}

// Opening the settings window and quitting are deliberately *not* here. They
// are the UI's own business — `MenuBarUI` owns those windows — and routing them
// through the orchestrator would only give it a reason to know about AppKit.
