import Accelerate
import AVFoundation
import Foundation
import Observation

/// Metering arithmetic, kept free of any state so both the live tap and the
/// offline probes can call it.
nonisolated enum AudioLevelMath {
    /// Per-buffer RMS and peak across all channels, on whatever native format
    /// the hardware handed us (24 kHz mono on the built-in mic, 48 kHz stereo
    /// on a typical interface — both are handled here, interleaved or not).
    ///
    /// Returns zeros for non-float buffers, which the input node never produces.
    static func measure(_ buffer: AVAudioPCMBuffer) -> (rms: Float, peak: Float) {
        let frames = vDSP_Length(buffer.frameLength)
        guard frames > 0, let channels = buffer.floatChannelData else { return (0, 0) }

        let channelCount = Int(buffer.format.channelCount)
        let interleaved = buffer.format.isInterleaved
        let stride = vDSP_Stride(interleaved ? channelCount : 1)

        var meanSquare: Float = 0
        var peak: Float = 0
        for channel in 0..<channelCount {
            let pointer = interleaved ? channels[0].advanced(by: channel) : channels[channel]
            var channelRMS: Float = 0
            var channelPeak: Float = 0
            vDSP_rmsqv(pointer, stride, &channelRMS, frames)
            vDSP_maxmgv(pointer, stride, &channelPeak, frames)
            meanSquare += channelRMS * channelRMS
            peak = max(peak, channelPeak)
        }
        let rms = (meanSquare / Float(max(channelCount, 1))).squareRoot()
        return (rms.isFinite ? rms : 0, peak.isFinite ? peak : 0)
    }

    static func decibels(linear: Float) -> Double {
        20 * log10(Double(max(linear, 1e-7)))
    }

    /// Maps a linear amplitude onto 0…1 across a dB window. Linear-in-dB is
    /// what makes a meter look right: quiet speech still moves the bar.
    static func normalized(linear: Float, floorDecibels: Double) -> Double {
        guard floorDecibels < 0 else { return 0 }
        let db = decibels(linear: linear)
        return min(1, max(0, (db - floorDecibels) / -floorDecibels))
    }
}

/// The UI-facing level meter.
///
/// The capture engine calls `ingest` from the audio thread; this class does the
/// hop to the main actor itself, coalescing bursts so the observable properties
/// change at most once per main-actor turn.
@Observable
@MainActor
final class AudioLevelMonitor {
    /// Smoothed 0…1 level for the bars.
    private(set) var level: Double = 0
    /// Smoothed 0…1 peak, with a slow fall-back for a peak-hold look.
    private(set) var peak: Double = 0
    /// Seconds captured so far, straight from the sample-accurate frame count.
    private(set) var elapsed: TimeInterval = 0
    /// True once samples are arriving, false after `reset()`.
    private(set) var isActive = false

    /// Bottom of the meter's dB window.
    var floorDecibels: Double = -60
    /// Rise/fall time constants: fast enough to feel live, slow enough not to flicker.
    var attackSeconds: Double = 0.03
    var releaseSeconds: Double = 0.25
    var peakReleaseSeconds: Double = 1.0

    private let mailbox = Mailbox()
    private var lastElapsed: TimeInterval?

    init() {}

    /// Clears the meter between recordings.
    func reset() {
        mailbox.clear()
        level = 0
        peak = 0
        elapsed = 0
        lastElapsed = nil
        isActive = false
    }

    /// Handler to hand straight to `AudioCaptureEngine.Callbacks.onLevel`.
    nonisolated func levelHandler() -> @Sendable (AudioLevelSample) -> Void {
        { [weak self] sample in self?.ingest(sample) }
    }

    /// Safe to call from the audio thread: it only takes a tiny lock and, at
    /// most once per pending turn, schedules the main-actor update.
    nonisolated func ingest(_ sample: AudioLevelSample) {
        guard mailbox.deposit(sample) else { return }
        Task { @MainActor [weak self] in
            self?.drain()
        }
    }

    private func drain() {
        guard let sample = mailbox.take() else { return }
        apply(sample)
    }

    private func apply(_ sample: AudioLevelSample) {
        let dt = min(0.5, max(0.001, sample.elapsed - (lastElapsed ?? sample.elapsed - 1.0 / 30.0)))
        lastElapsed = sample.elapsed

        let targetLevel = AudioLevelMath.normalized(linear: sample.rms, floorDecibels: floorDecibels)
        let targetPeak = AudioLevelMath.normalized(linear: sample.peak, floorDecibels: floorDecibels)

        let rising = targetLevel > level
        level += (targetLevel - level) * coefficient(dt: dt, tau: rising ? attackSeconds : releaseSeconds)
        if targetPeak > peak {
            peak = targetPeak
        } else {
            peak += (targetPeak - peak) * coefficient(dt: dt, tau: peakReleaseSeconds)
        }

        elapsed = sample.elapsed
        isActive = true
    }

    /// Time-based exponential smoothing, so an irregular buffer cadence (which
    /// is normal: buffer size is the hardware's choice) does not change the feel.
    private func coefficient(dt: Double, tau: Double) -> Double {
        guard tau > 0 else { return 1 }
        return 1 - exp(-dt / tau)
    }

    /// One-slot, newest-wins handoff from the audio thread to the main actor.
    private nonisolated final class Mailbox: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: AudioLevelSample?
        private var isScheduled = false

        /// Returns true when the caller should schedule a drain.
        func deposit(_ sample: AudioLevelSample) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            pending = sample
            guard !isScheduled else { return false }
            isScheduled = true
            return true
        }

        func take() -> AudioLevelSample? {
            lock.lock()
            defer { lock.unlock() }
            isScheduled = false
            let sample = pending
            pending = nil
            return sample
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            pending = nil
            isScheduled = false
        }
    }
}
