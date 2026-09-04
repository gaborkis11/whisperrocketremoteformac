import Foundation
import Observation
import WRCore
import WRNetwork

/// A ``PanelModelProviding`` that plays the whole choreography without a
/// microphone, a host or an orchestrator.
///
/// It exists so the panel could be built and *watched* before
/// `DictationController` did, and it stays afterwards as the only way to see
/// the rare states — a 503 while the model loads, the last five seconds of the
/// countdown, a focus change that cancelled the paste — on demand instead of by
/// waiting for one to happen.
///
/// The level it produces is a synthetic speech envelope: bursts with gaps, not
/// a sine wave, because a meter tuned against a sine looks wrong against a
/// voice. The countdown comes from the real `RecordingLimits` fed a simulated
/// 24 kHz frame count, so the numbers on screen are the numbers the audio
/// engine would produce.
@Observable
@MainActor
final class MockPanelModel: PanelModelProviding {
    private(set) var phase: DictationPhase = .idle
    private(set) var hostReachable: Bool?
    private(set) var level: Double = 0
    private(set) var peak: Double = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var countdown: Int?
    private(set) var attempt = 1
    let maxAttempts = UploadPlan.maxAttempts
    private(set) var recordings: [RecordingMeta] = []
    private(set) var summary: DictationSummary?
    private(set) var problem: DictationProblem?
    var shortcutDescription: String? = "⌘⇧Space"

    var hasFailedRecordings: Bool { recordings.contains { $0.status == .failed } }

    /// Set by a scenario to decide how the next upload ends.
    private var nextOutcome: Outcome = .success(.typed)
    /// How many attempts the next upload burns before it resolves.
    private var attemptsToBurn = 1

    private let limits = RecordingLimits.default
    private let sampleRate: Double = 24_000
    private var frameCount: Int64 = 0
    private var envelopePhase: Double = 0

    private var meterTask: Task<Void, Never>?
    private var scriptTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?

    enum Outcome: Sendable {
        case success(DeliveryOutcome, mode: DictationMode = .transcript, characters: Int = 412)
        case failure(DictationFailureKind, serverMessage: String?)
    }

    init(seedRecordings: Bool = true) {
        if seedRecordings {
            recordings = Self.seededRing()
        }
    }

    // MARK: - PanelModelProviding

    func toggleRecording() {
        if phase == .recording {
            stopRecording()
        } else {
            startRecording(hostReachable: true, startingFrame: 0)
        }
    }

    func resend(_ recordingID: UUID) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else { return }
        recordings[index].status = .sending
        attempt = 1
        scriptTask?.cancel()
        scriptTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self, !Task.isCancelled else { return }
            guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else { return }
            recordings[index].status = .sent
        }
    }

    // MARK: - Scenario playback

    func play(_ scenario: UIProbeScenario) {
        scriptTask?.cancel()
        scriptTask = Task { [weak self] in
            await self?.run(scenario)
        }
    }

    /// Puts the mock straight into the state a scenario *settles* on, with no
    /// timers and no animation.
    ///
    /// This is what the still-image probe renders. Waiting for a scenario to
    /// arrive somewhere would make the snapshots depend on timing, and a
    /// snapshot that is sometimes of the wrong frame is worse than none.
    func snapshot(_ scenario: UIProbeScenario) {
        stop()
        summary = nil
        problem = nil
        countdown = nil
        attempt = 1
        hostReachable = nil
        level = 0.62
        peak = 0.78
        elapsed = 47

        switch scenario {
        case .recording:
            phase = .recording
            hostReachable = true
        case .storedMode:
            phase = .recording
            hostReachable = false
        case .countdown:
            phase = .recording
            hostReachable = true
            elapsed = 287
            countdown = 13
        case .sending:
            phase = .sending
        case .retry:
            phase = .sending
            attempt = 2
        case .done:
            phase = .done
            summary = DictationSummary(characterCount: 412, delivery: .typed)
        case .clipboardOnly:
            phase = .done
            summary = DictationSummary(
                characterCount: 934,
                mode: .compose,
                delivery: .clipboardOnly(.focusChanged(appName: "Safari"))
            )
        case .failed:
            phase = .failed
            problem = DictationProblem(
                kind: .serviceUnavailable,
                serverMessage: "model warm-up in progress, try again in ~20s"
            )
        case .idle, .full:
            phase = .idle
        }

        // Every snapshot gets the same ring, so the only difference between two
        // images is the thing being compared.
        recordings = Self.seededRing()
        if phase == .sending { recordings[0].status = .sending }
    }

    func stop() {
        scriptTask?.cancel()
        scriptTask = nil
        uploadTask?.cancel()
        uploadTask = nil
        stopMeter()
    }

    private func run(_ scenario: UIProbeScenario) async {
        switch scenario {
        case .recording:
            nextOutcome = .success(.typed)
            startRecording(hostReachable: true, startingFrame: 0)

        case .storedMode:
            startRecording(hostReachable: nil, startingFrame: 0)
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            hostReachable = false

        case .countdown:
            // Drop in 30 s short of the ceiling: the countdown starts on the
            // very first tick and the auto-stop follows for real.
            nextOutcome = .success(.typed)
            startRecording(
                hostReachable: true,
                startingFrame: limits.countdownStartFrame(sampleRate: sampleRate)
            )

        case .sending:
            attemptsToBurn = 1
            nextOutcome = .success(.typed)
            beginSending(attempts: 1, resolveAfter: .seconds(600))

        case .retry:
            nextOutcome = .success(.typed)
            beginSending(attempts: 2, resolveAfter: .seconds(600))

        case .done:
            nextOutcome = .success(.typed)
            beginSending(attempts: 1, resolveAfter: .milliseconds(1200))

        case .clipboardOnly:
            nextOutcome = .success(
                .clipboardOnly(.focusChanged(appName: "Safari")),
                mode: .compose,
                characters: 934
            )
            beginSending(attempts: 1, resolveAfter: .milliseconds(1200))

        case .failed:
            nextOutcome = .failure(
                .serviceUnavailable,
                serverMessage: "model warm-up in progress, try again in ~20s"
            )
            beginSending(attempts: 3, resolveAfter: .milliseconds(1400))

        case .idle:
            phase = .idle

        case .full:
            await runFullLoop()
        }
    }

    /// The whole choreography, over and over: idle → recording (with the host
    /// dropping out and coming back) → sending → acknowledgement → idle.
    private func runFullLoop() async {
        while !Task.isCancelled {
            phase = .idle
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            startRecording(hostReachable: nil, startingFrame: 0)
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            hostReachable = true
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }

            nextOutcome = .success(.typed)
            stopRecording()
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }

            resolveUpload()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    // MARK: - Recording

    private func startRecording(hostReachable: Bool?, startingFrame: Int64) {
        self.hostReachable = hostReachable
        frameCount = startingFrame
        elapsed = limits.elapsed(frameCount: frameCount, sampleRate: sampleRate)
        countdown = limits.countdown(frameCount: frameCount, sampleRate: sampleRate)
        summary = nil
        problem = nil
        phase = .recording
        recordings.insert(
            RecordingMeta(id: UUID(), createdAt: .now, status: .pending, fileName: "mock.m4a"),
            at: 0
        )
        recordings = Array(recordings.prefix(3))
        startMeter()
    }

    private func stopRecording() {
        stopMeter()
        if !recordings.isEmpty {
            recordings[0].durationSeconds = elapsed
        }
        beginSending(attempts: attemptsToBurn, resolveAfter: .seconds(600))
    }

    // MARK: - Uploading

    private func beginSending(attempts: Int, resolveAfter delay: Duration) {
        attemptsToBurn = attempts
        attempt = 1
        countdown = nil
        phase = .sending
        markNewest(.sending)

        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            // Walk the attempt counter up at the real backoff cadence, so the
            // "attempt 2 of 3" line appears exactly when it would in anger.
            for step in 1..<max(attempts, 1) {
                let pause = UploadPlan.backoff[min(step - 1, UploadPlan.backoff.count - 1)]
                try? await Task.sleep(for: pause)
                guard let self, !Task.isCancelled, phase == .sending else { return }
                attempt = step + 1
            }
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, phase == .sending else { return }
            resolveUpload()
        }
    }

    private func resolveUpload() {
        switch nextOutcome {
        case .success(let delivery, let mode, let characters):
            summary = DictationSummary(characterCount: characters, mode: mode, delivery: delivery)
            problem = nil
            phase = .done
            markNewest(.sent)
        case .failure(let kind, let serverMessage):
            problem = DictationProblem(kind: kind, serverMessage: serverMessage)
            summary = nil
            phase = .failed
            markNewest(.failed)
        }
    }

    private func markNewest(_ status: RecordingMeta.Status) {
        guard !recordings.isEmpty else { return }
        recordings[0].status = status
    }

    // MARK: - Synthetic meter

    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            // 30 Hz: the same cadence `AudioLevelMonitor` coalesces down to.
            let interval = Duration.milliseconds(33)
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                tickMeter(dt: 1.0 / 30.0)
            }
        }
    }

    private func stopMeter() {
        meterTask?.cancel()
        meterTask = nil
        level = 0
        peak = 0
    }

    private func tickMeter(dt: Double) {
        guard phase == .recording else { return }

        frameCount += Int64(sampleRate * dt)
        elapsed = limits.elapsed(frameCount: frameCount, sampleRate: sampleRate)
        countdown = limits.countdown(frameCount: frameCount, sampleRate: sampleRate)

        if limits.hasReachedLimit(frameCount: frameCount, sampleRate: sampleRate) {
            // The ceiling is never silent: the panel counted down to it and the
            // upload starts exactly as it would after a manual stop.
            stopRecording()
            return
        }

        // Speech, roughly: a slow syllable rhythm under a slower phrase
        // envelope, with a gap where a person would draw breath.
        envelopePhase += dt
        let syllable = 0.5 + 0.5 * sin(envelopePhase * 11)
        let phrase = 0.5 + 0.5 * sin(envelopePhase * 0.7 + 1.1)
        let breath = phrase < 0.12 ? 0.0 : 1.0
        let target = min(1, max(0, 0.22 + 0.7 * syllable * phrase * breath))

        // Same attack/release shape as the real monitor, so the bars behave the
        // way they will against a microphone.
        let rising = target > level
        let tau = rising ? 0.03 : 0.25
        level += (target - level) * (1 - exp(-dt / tau))
        if target > peak {
            peak = target
        } else {
            peak += (target - peak) * (1 - exp(-dt / 1.0))
        }
    }

    // MARK: - Seed data

    /// A full ring with one of each interesting status, so the list and the
    /// menu-bar badge have something to show from the first frame.
    private static func seededRing() -> [RecordingMeta] {
        [
            RecordingMeta(
                id: UUID(),
                createdAt: Date(timeIntervalSinceNow: -95),
                durationSeconds: 42,
                status: .sent,
                fileName: "a.m4a"
            ),
            RecordingMeta(
                id: UUID(),
                createdAt: Date(timeIntervalSinceNow: -420),
                durationSeconds: 71,
                status: .failed,
                fileName: "b.m4a"
            ),
            RecordingMeta(
                id: UUID(),
                createdAt: Date(timeIntervalSinceNow: -1_800),
                durationSeconds: 128,
                status: .pending,
                fileName: "c.m4a"
            ),
        ]
    }
}
