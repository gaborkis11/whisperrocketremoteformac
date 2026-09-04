import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import WRCore

// MARK: - Errors

/// Everything the capture path can fail with. Every case carries enough text to
/// be shown to a human without a debugger attached.
nonisolated enum AudioCaptureError: Error, Sendable {
    case alreadyRecording
    case notRecording
    /// The chosen device could not be attached to the input audio unit.
    case deviceSelectionFailed(device: String, status: OSStatus)
    /// The input node reported a format we cannot record from (0 Hz / 0 channels),
    /// which is what a machine with no usable input device looks like.
    case invalidInputFormat(description: String)
    case engineStartFailed(underlying: String, microphoneAccess: String)
    case fileCreationFailed(url: URL, underlying: String)
    case converterUnavailable(source: String, destination: String)
    case conversionFailed(reason: String)
    case writeFailed(underlying: String)
    case writerClosed
    /// Stopped without a single encoded frame; the empty file was removed.
    case emptyRecording
    case unreadableRecording(url: URL, underlying: String)

    /// Human-readable, always present. `LocalizedError.errorDescription`
    /// (and therefore `localizedDescription`) forwards to this.
    var message: String {
        switch self {
        case .alreadyRecording:
            "A recording is already running."
        case .notRecording:
            "No recording is running."
        case .deviceSelectionFailed(let device, let status):
            "Could not switch the input to “\(device)” (CoreAudio status \(status))."
        case .invalidInputFormat(let description):
            "The audio input reported an unusable format: \(description)."
        case .engineStartFailed(let underlying, let access):
            "The audio engine did not start (microphone access: \(access)): \(underlying)"
        case .fileCreationFailed(let url, let underlying):
            "Could not create the recording file at \(url.path): \(underlying)"
        case .converterUnavailable(let source, let destination):
            "No converter from \(source) to \(destination)."
        case .conversionFailed(let reason):
            "Audio conversion failed: \(reason)"
        case .writeFailed(let underlying):
            "Writing the recording failed: \(underlying)"
        case .writerClosed:
            "The recording file is already closed."
        case .emptyRecording:
            "The recording contained no audio."
        case .unreadableRecording(let url, let underlying):
            "The finished recording at \(url.path) could not be read back: \(underlying)"
        }
    }
}

extension AudioCaptureError: LocalizedError {
    var errorDescription: String? { message }
}

// MARK: - Limits

/// Turns `WRCore.RecordingLimits` — which owns all the arithmetic and its unit
/// tests — into the running state the tap needs: how many frames of the next
/// buffer still fit, and which edges were crossed by admitting them.
///
/// Elapsed time is `frames / sampleRate`, never a wall clock, so it matches the
/// audio that actually reached the file and can be exercised offline (see
/// `--limits-probe`).
nonisolated struct RecordingLimitTracker: Sendable {
    enum Event: Equatable, Sendable {
        /// Fires once per whole second inside the countdown window.
        case countdown(remaining: Int)
        /// Fires exactly once, when the ceiling is hit.
        case limitReached
    }

    struct Admission: Equatable, Sendable {
        /// How many of the offered frames fit under the ceiling. Anything past
        /// the limit is refused here rather than trimmed later, so the file
        /// cannot overrun even if the caller is slow to stop.
        let acceptedFrames: Int64
        let events: [Event]
    }

    let limits: RecordingLimits
    private(set) var frames: Int64 = 0
    private(set) var elapsed: TimeInterval = 0
    private var lastCountdownSecond: Int?
    private var didReachLimit = false

    init(limits: RecordingLimits = .default) {
        self.limits = limits
    }

    mutating func admit(frames offered: Int64, sampleRate: Double) -> Admission {
        guard sampleRate > 0, offered > 0 else { return Admission(acceptedFrames: 0, events: []) }
        let budget = limits.maxFrames(sampleRate: sampleRate)
        // A zero budget means "no ceiling" in WRCore's vocabulary, not "refuse
        // everything" — admitting nothing would silently drop the recording.
        let accepted = budget > 0 ? max(0, min(offered, budget - frames)) : offered
        frames += accepted
        elapsed = limits.elapsed(frameCount: frames, sampleRate: sampleRate)

        var events: [Event] = []
        // `> 0` keeps the ladder at 30…1: at the ceiling the auto-stop speaks,
        // not a "0 seconds left" tick.
        if let second = limits.countdown(frameCount: frames, sampleRate: sampleRate),
           second > 0,
           second != lastCountdownSecond {
            lastCountdownSecond = second
            events.append(.countdown(remaining: second))
        }
        if !didReachLimit, limits.hasReachedLimit(frameCount: frames, sampleRate: sampleRate) {
            didReachLimit = true
            events.append(.limitReached)
        }
        return Admission(acceptedFrames: accepted, events: events)
    }
}

// MARK: - Level samples

/// One metering reading, taken on the *native* capture format before any
/// conversion, so the meter shows what the microphone hears.
nonisolated struct AudioLevelSample: Sendable {
    let rms: Float
    let peak: Float
    /// Seconds of audio captured so far, sample-accurate.
    let elapsed: TimeInterval
}

// MARK: - Engine

/// Microphone capture: `AVAudioEngine` input tap → metering → 16 kHz mono →
/// AAC `.m4a` at a URL the caller chose.
///
/// The caller passes the destination, which is how "every recording lands on
/// disk" stays a structural property: the ring store's URL *is* the capture
/// target, there is no separate save step that could be skipped.
///
/// Threading: `start`/`stop`/`cancel` are serialised by an internal lock and
/// are safe to call from the main actor. `onLevel` fires on the audio I/O
/// thread (keep it cheap — `AudioLevelMonitor.ingest` is built for it), while
/// `onCountdown`, `onLimitReached` and `onFailure` are dispatched on the main
/// queue so a handler may call `stop()` without deadlocking the audio thread.
nonisolated final class AudioCaptureEngine: @unchecked Sendable {
    struct Callbacks: Sendable {
        /// ~30 Hz metering, on the audio thread.
        var onLevel: (@Sendable (AudioLevelSample) -> Void)?
        /// Whole seconds remaining, once a second through the last 30 s.
        var onCountdown: (@Sendable (Int) -> Void)?
        /// The 5-minute ceiling was reached. The engine has already stopped
        /// accepting audio; the caller performs the same close-out as a manual
        /// stop (sound included) so the cut is never silent.
        var onLimitReached: (@Sendable () -> Void)?
        /// A failure during capture. The recording is finalised anyway on the
        /// next `stop()`, salvaging whatever was already encoded.
        var onFailure: (@Sendable (AudioCaptureError) -> Void)?

        init(
            onLevel: (@Sendable (AudioLevelSample) -> Void)? = nil,
            onCountdown: (@Sendable (Int) -> Void)? = nil,
            onLimitReached: (@Sendable () -> Void)? = nil,
            onFailure: (@Sendable (AudioCaptureError) -> Void)? = nil
        ) {
            self.onLevel = onLevel
            self.onCountdown = onCountdown
            self.onLimitReached = onLimitReached
            self.onFailure = onFailure
        }
    }

    private enum State {
        case idle
        /// Claimed by `start` before any hardware is touched, so two concurrent
        /// starts cannot both get past the guard.
        case starting
        case recording
        /// A write failed; buffers are dropped but the file is still finalised.
        case failing
        case stopping
    }

    /// Metering cadence. 30 Hz is the ceiling; if the hardware hands us fewer,
    /// slower buffers, every buffer still produces a sample.
    private let levelInterval: TimeInterval
    private let limits: RecordingLimits
    private let tapBufferSize: AVAudioFrameCount

    private let lock = NSLock()
    private var state: State = .idle
    private var engine: AVAudioEngine?
    private var writer: AudioSampleWriter?
    private var tracker = RecordingLimitTracker()
    private var callbacks = Callbacks()
    private var sourceSampleRate: Double = 0
    private var tapFormat: AVAudioFormat?
    private var recordedFailure: AudioCaptureError?
    /// Bumped on every `start`. A tap callback from a previous recording that
    /// is still in flight carries the old value and is dropped, so audio can
    /// never bleed from one recording's engine into the next one's file.
    private var generation: UInt64 = 0

    // Metering accumulators, so nothing is lost between emitted samples.
    private var pendingEnergy: Double = 0
    private var pendingFrames: Int = 0
    private var pendingPeak: Float = 0
    private var lastLevelEmit: TimeInterval = -.greatestFiniteMagnitude

    init(
        limits: RecordingLimits = .default,
        levelInterval: TimeInterval = 1.0 / 30.0,
        tapBufferSize: AVAudioFrameCount = 2_048
    ) {
        self.limits = limits
        self.levelInterval = levelInterval
        self.tapBufferSize = tapBufferSize
    }

    // MARK: Public surface

    static var microphoneAuthorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .starting, .recording, .failing: return true
        case .idle, .stopping: return false
        }
    }

    /// The native format the hardware is actually delivering, while a recording
    /// is running. Worth surfacing: it is never assumed, and it differs per
    /// device (48 kHz built-in mic, 24 kHz AirPods).
    var inputFormat: AVAudioFormat? {
        lock.lock()
        defer { lock.unlock() }
        return tapFormat
    }

    /// The failure reported during the current or most recent capture, if any.
    /// It survives `stop()`, so a caller can tell a clean recording from a
    /// salvaged one; `start()` clears it.
    var lastFailure: AudioCaptureError? {
        lock.lock()
        defer { lock.unlock() }
        return recordedFailure
    }

    /// Seconds of audio captured so far.
    var elapsed: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return tracker.elapsed
    }

    /// Starts capturing into `url`.
    ///
    /// - Parameter device: `nil` records from the system default input. A
    ///   non-nil device is attached to this engine's input unit only — the
    ///   machine-wide default input is never touched.
    func start(
        writingTo url: URL,
        device: AudioInputDevice?,
        callbacks: Callbacks = Callbacks()
    ) throws(AudioCaptureError) {
        lock.lock()
        guard case .idle = state else {
            lock.unlock()
            throw .alreadyRecording
        }
        state = .starting
        lock.unlock()

        // A fresh engine per recording: device selection and the input format
        // are both read at instantiation time, so reuse would strand us on the
        // previously selected microphone.
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let tapFormat: AVAudioFormat
        let writer: AudioSampleWriter
        do throws(AudioCaptureError) {
            if let device {
                try Self.attach(device: device, to: inputNode)
            }
            // Always asked at runtime, never assumed: the built-in mic reports
            // 48 kHz, AirPods 24 kHz, an interface something else again.
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw AudioCaptureError.invalidInputFormat(description: format.description)
            }
            tapFormat = format
            writer = try AudioSampleWriter(url: url, sourceFormat: format)
        } catch {
            lock.lock()
            state = .idle
            lock.unlock()
            throw error
        }

        lock.lock()
        self.engine = engine
        self.writer = writer
        self.callbacks = callbacks
        self.tracker = RecordingLimitTracker(limits: limits)
        self.sourceSampleRate = tapFormat.sampleRate
        self.tapFormat = tapFormat
        self.recordedFailure = nil
        self.pendingEnergy = 0
        self.pendingFrames = 0
        self.pendingPeak = 0
        self.lastLevelEmit = -.greatestFiniteMagnitude
        self.generation &+= 1
        let generation = self.generation
        self.state = .recording
        lock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: tapFormat) { [weak self] buffer, _ in
            self?.receive(buffer, generation: generation)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Unwind completely: no tap left installed, no half-open AAC
            // container on disk, and the state back to idle so a retry works.
            inputNode.removeTap(onBus: 0)
            lock.lock()
            self.state = .idle
            self.engine = nil
            self.writer = nil
            self.callbacks = Callbacks()
            lock.unlock()
            writer.abort()
            throw .engineStartFailed(
                underlying: String(describing: error),
                microphoneAccess: Self.describe(Self.microphoneAuthorization)
            )
        }
    }

    /// Stops capturing and finalises the file.
    ///
    /// A failure reported through `onFailure` mid-capture does not make this
    /// throw: whatever was encoded is still closed properly and handed back,
    /// because a partial recording beats a lost one.
    @discardableResult
    func stop() throws(AudioCaptureError) -> AudioRecordingFile {
        lock.lock()
        switch state {
        case .idle, .starting, .stopping:
            // `.starting` belongs here: `start` has not handed over an engine
            // yet, and it resets the state itself on either outcome.
            lock.unlock()
            throw .notRecording
        case .recording, .failing:
            state = .stopping
        }
        let engine = self.engine
        lock.unlock()

        // Outside the lock on purpose: `engine.stop()` waits for the I/O thread,
        // which may be sitting in `receive(_:)` waiting for this same lock.
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)

        lock.lock()
        let writer = self.writer
        self.writer = nil
        self.engine = nil
        self.callbacks = Callbacks()
        self.state = .idle
        lock.unlock()

        guard let writer else { throw .notRecording }
        guard writer.framesWritten > 0 else {
            writer.abort()
            throw .emptyRecording
        }
        return try writer.finish()
    }

    /// Stops and throws the recording away (start-up failures, user cancel).
    func cancel() {
        lock.lock()
        switch state {
        case .idle, .starting, .stopping:
            lock.unlock()
            return
        case .recording, .failing:
            state = .stopping
        }
        let engine = self.engine
        lock.unlock()

        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)

        lock.lock()
        let writer = self.writer
        self.writer = nil
        self.engine = nil
        self.callbacks = Callbacks()
        self.state = .idle
        lock.unlock()

        writer?.abort()
    }

    // MARK: Capture path

    /// What the locked section decided should be announced, emitted afterwards
    /// so no callback ever runs while the lock is held.
    private struct Emission {
        var level: AudioLevelSample?
        var events: [RecordingLimitTracker.Event] = []
        var failure: AudioCaptureError?
    }

    private func receive(_ buffer: AVAudioPCMBuffer, generation: UInt64) {
        let emission = ingest(buffer, generation: generation)
        deliver(emission, generation: generation)
    }

    private func ingest(_ buffer: AVAudioPCMBuffer, generation: UInt64) -> Emission {
        lock.lock()
        defer { lock.unlock() }
        guard case .recording = state, generation == self.generation, let writer else { return Emission() }

        var emission = Emission()

        // Metering happens on the native format, before conversion.
        let measurement = AudioLevelMath.measure(buffer)
        pendingEnergy += Double(measurement.rms * measurement.rms) * Double(buffer.frameLength)
        pendingFrames += Int(buffer.frameLength)
        pendingPeak = max(pendingPeak, measurement.peak)

        let admission = tracker.admit(frames: Int64(buffer.frameLength), sampleRate: sourceSampleRate)
        emission.events = admission.events

        if admission.acceptedFrames > 0 {
            let toWrite: AVAudioPCMBuffer?
            if admission.acceptedFrames == Int64(buffer.frameLength) {
                toWrite = buffer
            } else {
                // Last buffer before the ceiling: keep only the frames that fit.
                toWrite = Self.prefix(of: buffer, frames: AVAudioFrameCount(admission.acceptedFrames))
            }
            if let toWrite {
                do {
                    try writer.write(toWrite)
                } catch {
                    state = .failing
                    recordedFailure = error
                    emission.failure = error
                }
            }
        }

        if pendingFrames > 0, tracker.elapsed - lastLevelEmit >= levelInterval {
            lastLevelEmit = tracker.elapsed
            emission.level = AudioLevelSample(
                rms: Float((pendingEnergy / Double(pendingFrames)).squareRoot()),
                peak: pendingPeak,
                elapsed: tracker.elapsed
            )
            pendingEnergy = 0
            pendingFrames = 0
            pendingPeak = 0
        }
        return emission
    }

    private func deliver(_ emission: Emission, generation: UInt64) {
        lock.lock()
        let callbacks = self.callbacks
        lock.unlock()

        if let level = emission.level {
            callbacks.onLevel?(level)
        }
        guard !emission.events.isEmpty || emission.failure != nil else { return }
        let events = emission.events
        let failure = emission.failure
        // Hop off the audio thread: handlers routinely call back into stop().
        DispatchQueue.main.async { [weak self] in
            // The recording may have been stopped in the meantime — a manual
            // stop racing the ceiling, say. Nothing announces itself afterwards.
            guard self?.isCurrent(generation) == true else { return }
            for event in events {
                switch event {
                case .countdown(let remaining): callbacks.onCountdown?(remaining)
                case .limitReached: callbacks.onLimitReached?()
                }
            }
            if let failure { callbacks.onFailure?(failure) }
        }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == self.generation else { return false }
        switch state {
        case .recording, .failing: return true
        case .idle, .starting, .stopping: return false
        }
    }

    // MARK: Helpers

    /// Points this engine's input unit at one specific device. Uses
    /// `kAudioOutputUnitProperty_CurrentDevice` on the input node's audio unit,
    /// which is process-local — the system-wide default input is untouched.
    private static func attach(device: AudioInputDevice, to inputNode: AVAudioInputNode) throws(AudioCaptureError) {
        guard let unit = inputNode.audioUnit else {
            throw .deviceSelectionFailed(device: device.name, status: OSStatus(kAudioUnitErr_Uninitialized))
        }
        var deviceID = device.deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw .deviceSelectionFailed(device: device.name, status: status)
        }
    }

    /// A copy of the first `frames` frames, format-agnostic (interleaved or not).
    private static func prefix(of buffer: AVAudioPCMBuffer, frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard frames > 0, frames <= buffer.frameLength else { return nil }
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: frames) else { return nil }
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }

        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == destination.count else { return nil }
        for index in 0..<source.count {
            guard let src = source[index].mData, let dst = destination[index].mData else { return nil }
            let byteCount = Int(frames) * bytesPerFrame
            memcpy(dst, src, byteCount)
            destination[index].mDataByteSize = UInt32(byteCount)
        }
        copy.frameLength = frames
        return copy
    }

    static func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }
}
