import Foundation

/// The 5-minute capture ceiling, expressed in frames so the audio engine can
/// enforce it sample-accurately from its own tap counter instead of racing a
/// timer.
///
/// The auto-stop is never silent: the panel counts down over the last
/// ``countdownThreshold`` seconds and the stop sound plays exactly as it does
/// for a manual stop.
public struct RecordingLimits: Equatable, Sendable {
    public static let `default` = RecordingLimits()

    public let maxDuration: TimeInterval
    public let countdownThreshold: TimeInterval

    public init(maxDuration: TimeInterval = 300, countdownThreshold: TimeInterval = 30) {
        self.maxDuration = maxDuration
        self.countdownThreshold = countdownThreshold
    }

    /// The frame budget at `sampleRate`. A non-positive rate has no meaningful
    /// budget and yields 0, which ``hasReachedLimit(frameCount:sampleRate:)``
    /// reads as "never auto-stop" rather than "stop immediately".
    public func maxFrames(sampleRate: Double) -> Int64 {
        guard sampleRate > 0 else { return 0 }
        return Int64((maxDuration * sampleRate).rounded())
    }

    /// The frame at which the panel starts counting down.
    public func countdownStartFrame(sampleRate: Double) -> Int64 {
        guard sampleRate > 0 else { return 0 }
        return Int64((max(maxDuration - countdownThreshold, 0) * sampleRate).rounded())
    }

    public func hasReachedLimit(frameCount: Int64, sampleRate: Double) -> Bool {
        let budget = maxFrames(sampleRate: sampleRate)
        return budget > 0 && frameCount >= budget
    }

    public func elapsed(frameCount: Int64, sampleRate: Double) -> TimeInterval {
        guard sampleRate > 0, frameCount > 0 else { return 0 }
        return Double(frameCount) / sampleRate
    }

    public func remaining(frameCount: Int64, sampleRate: Double) -> TimeInterval {
        max(maxDuration - elapsed(frameCount: frameCount, sampleRate: sampleRate), 0)
    }

    /// Whole seconds left, or `nil` while still outside the countdown window.
    /// Rounds up, so "30" shows for the whole second between 30.0 s and 29.0 s
    /// left and the display never skips a number.
    public func countdown(frameCount: Int64, sampleRate: Double) -> Int? {
        guard sampleRate > 0 else { return nil }
        let left = remaining(frameCount: frameCount, sampleRate: sampleRate)
        guard left <= countdownThreshold else { return nil }
        return Int(left.rounded(.up))
    }
}
