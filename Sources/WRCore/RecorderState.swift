import Foundation

/// What the recorder is doing right now.
///
/// The health probe runs *alongside* the capture instead of gating it, so a
/// recording always starts with `hostReachable == nil` and only learns the
/// answer later — a slow or dead host must never cost the user their first
/// words.
public enum RecorderState: Equatable, Sendable {
    case idle
    case recording(hostReachable: Bool?)

    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    /// `nil` while idle, and while recording until the probe answers.
    public var hostReachable: Bool? {
        if case .recording(let reachable) = self { return reachable }
        return nil
    }
}

/// Everything that can move the recorder.
public enum RecorderEvent: Equatable, Sendable {
    case start
    case stop
    case healthResult(reachable: Bool)
}

public enum RecorderTransitionError: Error, Equatable, Sendable {
    /// `start` while already recording — the toggle is out of sync.
    case alreadyRecording
    /// `stop` while idle — the toggle is out of sync.
    case notRecording
    /// The probe outlived the recording it was started for. A benign race
    /// (the user stopped before the host answered); callers drop the result.
    case healthResultWhileIdle
}

extension RecorderState {
    /// The whole state machine, as one pure function.
    public func applying(_ event: RecorderEvent) -> Result<RecorderState, RecorderTransitionError> {
        switch (self, event) {
        case (.idle, .start):
            return .success(.recording(hostReachable: nil))
        case (.recording, .start):
            return .failure(.alreadyRecording)

        case (.recording, .stop):
            return .success(.idle)
        case (.idle, .stop):
            return .failure(.notRecording)

        case (.recording, .healthResult(let reachable)):
            // Only the reachability field moves; a health answer never starts
            // or stops a capture.
            return .success(.recording(hostReachable: reachable))
        case (.idle, .healthResult):
            return .failure(.healthResultWhileIdle)
        }
    }

    /// Applies `event` in place, returning the rejection reason when the
    /// transition is not allowed (the state is then left untouched).
    @discardableResult
    public mutating func apply(_ event: RecorderEvent) -> RecorderTransitionError? {
        switch applying(event) {
        case .success(let next):
            self = next
            return nil
        case .failure(let error):
            return error
        }
    }
}
