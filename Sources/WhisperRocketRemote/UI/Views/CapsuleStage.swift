import Foundation

/// What the capsule is showing — a *presentation* state, not a phase.
///
/// There is deliberately no `.cancelled` in ``DictationPhase`` and no new event
/// in the orchestrator: cancelling puts the controller back in `.idle`, exactly
/// as it does today, and the flash of "Cancelled" the user sees on the way out
/// is something the UI adds on top. Inventing a phase for it would have meant
/// the audio layer knowing about a fade-out.
nonisolated enum CapsuleStage: Equatable, Sendable {
    case recording
    case sending
    case done
    case failed
    case cancelled

    /// `nil` means "nothing to show" — idle, with no cancellation to announce.
    ///
    /// The flash wins over the phase because the two are read a moment apart:
    /// Escape raises the flag and *then* asks the controller to stop, so for one
    /// frame the phase is still `.recording` while the answer is already
    /// "cancelled".
    init?(phase: DictationPhase, showingCancelled: Bool) {
        if showingCancelled {
            self = .cancelled
            return
        }
        switch phase {
        case .idle: return nil
        case .recording: self = .recording
        case .sending: self = .sending
        case .done: self = .done
        case .failed: self = .failed
        }
    }

    /// Whether the microphone is open, which is the one stage that samples the
    /// waveform rather than merely drawing what it already has.
    var isLive: Bool { self == .recording }

    /// A stray click elsewhere must not take the capsule away from something
    /// still in progress. A failure is the exception, exactly as in the panel:
    /// clicking away is the user saying "read, move on".
    var holdsOpen: Bool { self != .failed }
}
