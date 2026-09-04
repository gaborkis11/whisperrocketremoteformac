import AppKit
import AVFoundation
import Foundation
import Observation
import WRCore
import WRNetwork

/// The one object that owns the dictation flow: capture engine, recording ring,
/// both network clients, settings, keychain, sounds and auto-typing.
///
/// Everything else — the status item, the panel, the recording list — only
/// reads the observable state below. The two little state machines the plan
/// calls for live here in their WRCore form: `RecorderState` for the capture,
/// and per-recording upload state inside `RecordingStore`.
///
/// Ordering rules that the code cannot show on its own:
///
/// - The health probe runs *alongside* the capture, never before it. A dead
///   host must not cost the user their first words.
/// - The 5-minute auto-stop takes the exact same path as a manual stop, stop
///   click included: a silent cut is a silent data loss.
/// - The clipboard is written for every successful dictation, and *never*
///   cleared for an empty one.
@Observable
@MainActor
final class DictationController {
    // MARK: - Public, UI-facing state

    enum Phase: Equatable, Sendable {
        case idle
        case recording
        case sending
        case done
        case failed
    }

    /// Why the text was not typed into the app that had focus.
    enum PasteSkip: Equatable, Sendable {
        case disabled
        case notTrusted
        case focusChanged(expected: String?, actual: String?)
        case postFailed

        var message: String {
            switch self {
            case .disabled:
                "Copied to the clipboard."
            case .notTrusted:
                "Copied to the clipboard — Accessibility permission is missing, so nothing was typed."
            case .focusChanged(let expected, let actual):
                "Copied to the clipboard — focus moved from \(expected ?? "the previous app") to "
                    + "\(actual ?? "another app"), so nothing was typed."
            case .postFailed:
                "Copied to the clipboard — the ⌘V event could not be sent."
            }
        }
    }

    enum PasteOutcome: Equatable, Sendable {
        case pasted
        case clipboardOnly(PasteSkip)

        var didPaste: Bool { self == .pasted }

        var message: String {
            switch self {
            case .pasted: "Pasted into the focused app."
            case .clipboardOnly(let skip): skip.message
            }
        }
    }

    struct Delivery: Equatable, Sendable {
        let recordingID: UUID
        let text: String
        let mode: DictationMode
        let enhanced: Bool
        let paste: PasteOutcome
        /// Wall time of the successful upload attempt, request to response.
        let uploadSeconds: TimeInterval
    }

    enum Problem: Equatable, Sendable {
        /// No usable host in settings yet.
        case notConfigured(String)
        /// The capture itself broke — nothing was recorded, or the file could
        /// not be closed.
        case capture(String)
        case upload(kind: DictationFailureKind, serverMessage: String?, attempts: Int)
        /// The host answered 2xx with an empty body, or 422. The clipboard was
        /// deliberately left alone.
        case noSpeech

        var message: String {
            switch self {
            case .notConfigured(let detail): detail
            case .capture(let detail): detail
            case .upload(let kind, let server, let attempts):
                attempts > 1
                    ? "\(kind.message)\(server.map { " (\($0))" } ?? "") — gave up after \(attempts) attempts."
                    : "\(kind.message)\(server.map { " (\($0))" } ?? "")"
            case .noSpeech:
                "No speech in that recording — the clipboard was left untouched."
            }
        }
    }

    struct FailureInfo: Equatable, Sendable {
        let recordingID: UUID?
        let problem: Problem
        var message: String { problem.message }
    }

    /// Why a running capture was closed out.
    enum StopReason: Equatable, Sendable {
        case manual
        /// The 5-minute ceiling. Identical handling, sound included.
        case limitReached
        case audioConfigurationChanged(String)

        var label: String {
            switch self {
            case .manual: "manual"
            case .limitReached: "limitReached"
            case .audioConfigurationChanged(let detail): "audioConfigurationChanged(\(detail))"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var recorderState: RecorderState = .idle
    /// `nil` until the parallel `/health` probe answers — that is the banner's
    /// "unknown yet" state, not "unreachable".
    var hostReachable: Bool? { recorderState.hostReachable }
    private(set) var lastHealth: HealthStatus?
    /// The banner text while the host will not take a dictation, `nil` otherwise.
    var storedModeBanner: String? {
        guard recorderState.isRecording, hostReachable == false else { return nil }
        return lastHealth?.bannerMessage ?? "The host cannot be reached — the recording will be stored."
    }

    let levelMonitor = AudioLevelMonitor()
    /// Whole seconds left, over the last 30 s of a recording; `nil` otherwise.
    private(set) var countdown: Int?
    /// Newest first — the order the list shows them in.
    private(set) var recordings: [RecordingMeta] = []
    /// Drives the status-item badge.
    private(set) var hasFailedRecordings = false
    /// 1-based attempt number while an upload is in flight, 0 otherwise.
    private(set) var attempt = 0
    let maxAttempts = UploadPlan.maxAttempts
    /// "2/3" while sending, `nil` otherwise.
    var attemptLabel: String? {
        attempt > 0 ? "\(attempt)/\(maxAttempts)" : nil
    }
    private(set) var sendingRecordingID: UUID?
    private(set) var lastDelivery: Delivery?
    private(set) var lastFailure: FailureInfo?
    /// Set when the saved microphone has disappeared and the system default is
    /// being used instead.
    private(set) var inputDeviceWarning: String?
    /// A recording ring that could not be opened at all — nothing can be
    /// captured until it is fixed.
    private(set) var storeFailure: String?

    var isRecording: Bool { recorderState.isRecording }
    /// True while a recording or an upload is in flight — what `--flow-probe`
    /// waits on, and what the panel uses to keep itself open.
    var isBusy: Bool {
        recorderState.isRecording || uploadTask != nil || !queue.isEmpty
    }

    let settings: Settings
    let soundPlayer: SoundPlayer

    /// Step-by-step trace sink. `nil` in normal operation; `--flow-probe`
    /// installs one so the whole chain lands in a log file.
    @ObservationIgnored var traceHandler: (@MainActor (String) -> Void)?

    // MARK: - Plumbing

    @ObservationIgnored private let engine: AudioCaptureEngine
    @ObservationIgnored private let store: RecordingStore
    @ObservationIgnored private let dictationClient: DictationClient
    @ObservationIgnored private let healthClient: HealthClient
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let tokenSource: TokenSource

    /// What a running capture needs to remember about itself.
    private struct ActiveRecording {
        let id: UUID
        let fileURL: URL
        /// The app that had focus when the hotkey was pressed — the only app
        /// this dictation is allowed to type into.
        let frontmostBundleID: String?
        let sampleRate: Double
        let channelCount: UInt32
        let startedAt: Date
    }

    @ObservationIgnored private var active: ActiveRecording?
    @ObservationIgnored private var configurationWatcher: AudioConfigurationWatcher?
    /// Bumped on every start and stop, so a `/health` answer that outlived its
    /// recording is dropped instead of raising a banner over the next one.
    @ObservationIgnored private var healthGeneration: UInt64 = 0
    /// Serial upload queue — the host takes one dictation at a time anyway.
    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var uploadTask: Task<Void, Never>?
    /// Per-recording paste targets, captured when the recording (or the resend)
    /// was asked for.
    @ObservationIgnored private var pasteTargets: [UUID: String] = [:]

    // MARK: - Init

    init(
        settings: Settings,
        store: RecordingStore,
        keychain: KeychainStore = KeychainStore(),
        tokenSource: TokenSource? = nil,
        engine: AudioCaptureEngine = AudioCaptureEngine(),
        dictationClient: DictationClient = DictationClient(),
        healthClient: HealthClient = HealthClient(),
        soundPlayer: SoundPlayer? = nil
    ) {
        self.settings = settings
        self.store = store
        self.keychain = keychain
        self.tokenSource = tokenSource ?? .keychain(keychain)
        self.engine = engine
        self.dictationClient = dictationClient
        self.healthClient = healthClient
        self.soundPlayer = soundPlayer ?? SoundPlayer(isEnabled: settings.soundsEnabled)
        refreshRecordings()
    }

    /// The everyday construction: the ring in Application Support, the token in
    /// the keychain.
    convenience init(settings: Settings = Settings()) throws {
        try self.init(
            settings: settings,
            store: RecordingStore(directory: RecordingStore.defaultDirectory())
        )
    }

    // MARK: - Recording

    /// The hotkey. One press starts, the next one stops.
    func toggle() {
        if recorderState.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !recorderState.isRecording else { return }

        lastDelivery = nil
        lastFailure = nil
        countdown = nil
        inputDeviceWarning = nil
        levelMonitor.reset()
        soundPlayer.isEnabled = settings.soundsEnabled

        // The paste target is read before anything else can move focus.
        let frontmost = AutoPaste.frontmostBundleID

        let reservation: RecordingStore.Reservation
        do {
            reservation = try store.reserve()
        } catch {
            storeFailure = String(describing: error)
            fail(FailureInfo(recordingID: nil, problem: .capture("Could not reserve a slot in the recording store: \(error)")))
            return
        }
        storeFailure = nil
        refreshRecordings()
        trace("reserved \(reservation.meta.id) -> \(reservation.fileURL.lastPathComponent)")

        let resolution = AudioDeviceList.resolve(AudioInputSelection(storedUID: settings.inputDeviceUID))
        if case .missing(let uid, let fallback) = resolution {
            inputDeviceWarning = "The saved microphone (\(uid)) is gone; recording from "
                + "\(fallback?.name ?? "the system default") instead."
        }
        trace("input device: \(resolution.effectiveDevice?.name ?? "<system default>")")

        do {
            try engine.start(
                writingTo: reservation.fileURL,
                device: resolution.deviceToUse,
                callbacks: makeCallbacks()
            )
        } catch {
            // The slot is already in the ring and its audio never happened. A
            // failed entry is the honest thing to show: the user pressed the
            // key and got nothing, and the panel says why.
            try? store.markFailed(id: reservation.meta.id)
            refreshRecordings()
            fail(FailureInfo(recordingID: reservation.meta.id, problem: .capture(error.message)))
            return
        }

        let format = engine.inputFormat
        active = ActiveRecording(
            id: reservation.meta.id,
            fileURL: reservation.fileURL,
            frontmostBundleID: frontmost,
            sampleRate: format?.sampleRate ?? 0,
            channelCount: format?.channelCount ?? 0,
            startedAt: Date()
        )
        pasteTargets[reservation.meta.id] = frontmost
        recorderState.apply(.start)
        phase = .recording
        soundPlayer.play(.start)
        trace("recording started; tap format \(format?.description ?? "<none>"); frontmost=\(frontmost ?? "<none>")")

        startHealthProbe()
        configurationWatcher = AudioConfigurationWatcher { [weak self] change in
            self?.handleConfigurationChange(change)
        }
    }

    func stopRecording() {
        stopRecording(reason: .manual)
    }

    /// Stops without uploading. The audio is *kept*, as a `pending` entry the
    /// user can send later — "never lose a recording" outranks "tidy list", and
    /// a discarded five minutes is exactly the loss this app exists to prevent.
    func cancelRecording() {
        guard recorderState.isRecording, let active else { return }
        endCapture()
        soundPlayer.play(.stop)
        do {
            let file = try engine.stop()
            try? store.updateDuration(file.duration, id: active.id)
            trace(String(format: "cancelled after %.3f s — kept as pending", file.duration))
        } catch {
            try? store.markFailed(id: active.id)
            trace("cancel: nothing was captured (\(error.message))")
        }
        refreshRecordings()
        phase = .idle
    }

    private func stopRecording(reason: StopReason) {
        guard recorderState.isRecording, let active else { return }

        endCapture()
        // Every stop sounds the same, ceiling included.
        soundPlayer.play(.stop)

        do {
            let file = try engine.stop()
            try? store.updateDuration(file.duration, id: active.id)
            refreshRecordings()
            trace(String(
                format: "stopped (%@): %.3f s, %d bytes, %.0f Hz %@",
                reason.label, file.duration, file.byteCount, file.sampleRate, file.formatDescription
            ))
            if let captureFailure = engine.lastFailure {
                trace("capture reported a failure mid-recording, salvaged: \(captureFailure.message)")
            }
            enqueue(active.id)
        } catch {
            engine.cancel()
            try? store.markFailed(id: active.id)
            refreshRecordings()
            trace("stop failed (\(reason.label)): \(error.message)")
            fail(FailureInfo(recordingID: active.id, problem: .capture(error.message)))
        }
    }

    /// Everything a stop does before the file is closed, shared by the manual
    /// stop, the ceiling, the device-loss path and cancel — so no route can
    /// forget to drop the watcher or the stale health answer.
    private func endCapture() {
        recorderState.apply(.stop)
        healthGeneration &+= 1
        configurationWatcher?.invalidate()
        configurationWatcher = nil
        countdown = nil
        active = nil
        soundPlayer.isEnabled = settings.soundsEnabled
    }

    private func makeCallbacks() -> AudioCaptureEngine.Callbacks {
        AudioCaptureEngine.Callbacks(
            onLevel: levelMonitor.levelHandler(),
            onCountdown: { [weak self] remaining in
                Task { @MainActor in
                    self?.countdown = remaining
                    self?.trace("countdown: \(remaining) s left")
                }
            },
            onLimitReached: { [weak self] in
                Task { @MainActor in
                    self?.trace("recording ceiling reached — closing out exactly like a manual stop")
                    self?.stopRecording(reason: .limitReached)
                }
            },
            onFailure: { [weak self] error in
                Task { @MainActor in self?.trace("capture failure: \(error.message)") }
            }
        )
    }

    // MARK: - Health probe

    /// Runs next to the capture, never in front of it.
    private func startHealthProbe() {
        healthGeneration &+= 1
        let generation = healthGeneration

        guard let config = try? resolveHost() else {
            lastHealth = nil
            recorderState.apply(.healthResult(reachable: false))
            trace("health: skipped — no host configured")
            return
        }
        let endpoint = EndpointConfig(url: config.healthURL, token: config.token)
        let client = healthClient
        let started = Date()
        Task { [weak self] in
            let status = await client.check(config: endpoint)
            guard let self, self.healthGeneration == generation else { return }
            self.lastHealth = status
            // `apply` refuses a health answer once the recording is over, which
            // is the benign race of stopping before the host replies.
            self.recorderState.apply(.healthResult(reachable: status.isReady))
            self.trace(String(
                format: "health: %@ (%.0f ms) -> hostReachable=%@",
                status.label, Date().timeIntervalSince(started) * 1000, String(describing: status.isReady)
            ))
        }
    }

    // MARK: - Audio configuration changes

    /// A device vanishing mid-recording looks the same as half a dozen benign
    /// renegotiations, so only two things count as a real loss: the engine
    /// stopped, or the input format actually changed under us.
    private func handleConfigurationChange(_ change: AudioConfigurationWatcher.Change) {
        guard recorderState.isRecording, let active else { return }

        let formatChanged = change.sampleRate > 0
            && (change.sampleRate != active.sampleRate || change.channelCount != active.channelCount)
        let stopped = !change.engineIsRunning || !engine.isRecording

        guard stopped || formatChanged else {
            trace(String(
                format: "audio configuration change ignored (engine running, format still %.0f Hz / %u ch)",
                change.sampleRate, change.channelCount
            ))
            return
        }
        let detail = String(
            format: "running=%@ format %.0f/%u -> %.0f/%u",
            String(describing: change.engineIsRunning),
            active.sampleRate, active.channelCount, change.sampleRate, change.channelCount
        )
        trace("audio configuration change: \(detail) — closing the recording out")
        // Whatever is already encoded is good audio; close out and upload it.
        stopRecording(reason: .audioConfigurationChanged(detail))
    }

    // MARK: - Upload queue

    /// Re-sends a recording that failed, with a fresh attempt counter.
    func resend(id: UUID) {
        guard let meta = store.recording(id: id), meta.status != .sending else { return }
        guard !queue.contains(id), sendingRecordingID != id else { return }
        // The paste target is "the app you were in when you asked for it".
        pasteTargets[id] = AutoPaste.frontmostBundleID
        try? store.markPending(id: id)
        refreshRecordings()
        trace("manual resend requested for \(id)")
        enqueue(id)
    }

    func resendAllFailed() {
        for meta in recordings where meta.status == .failed {
            resend(id: meta.id)
        }
    }

    private func enqueue(_ id: UUID) {
        queue.append(id)
        // Set here rather than in `upload`: the queue drains on a Task, so the
        // panel would otherwise still read `.recording` for a turn after the
        // microphone had already been closed.
        phase = .sending
        pump()
    }

    private func pump() {
        guard uploadTask == nil, !queue.isEmpty else { return }
        uploadTask = Task { [weak self] in
            while let self, !self.queue.isEmpty {
                let id = self.queue.removeFirst()
                await self.upload(id: id)
            }
            self?.uploadTask = nil
            self?.pump()
        }
    }

    private func upload(id: UUID) async {
        guard let meta = store.recording(id: id) else { return }
        let fileURL = store.fileURL(for: meta)

        let config: HostConfig
        do {
            config = try resolveHost()
        } catch {
            try? store.markFailed(id: id)
            refreshRecordings()
            fail(FailureInfo(
                recordingID: id,
                problem: .notConfigured("No host configured yet — the recording is stored and can be re-sent. (\(error))")
            ))
            return
        }
        let endpoint = EndpointConfig(url: config.dictateURL, token: config.token)

        try? store.markSending(id: id)
        sendingRecordingID = id
        phase = .sending
        refreshRecordings()
        trace("upload \(id) -> \(config.dictateURL.absoluteString) "
            + "(token: \(config.hasToken ? "present" : "MISSING"), file: \(fileURL.lastPathComponent))")

        var attemptNumber = 1
        while true {
            attempt = attemptNumber
            let started = Date()
            let outcome = await dictationClient.send(fileURL: fileURL, config: endpoint)
            let seconds = Date().timeIntervalSince(started)

            switch outcome {
            case .success(let text, let mode, let enhanced):
                trace(String(
                    format: "attempt %d/%d succeeded in %.0f ms (mode=%@ enhanced=%@ %d chars)",
                    attemptNumber, maxAttempts, seconds * 1000,
                    mode.rawValue, String(describing: enhanced), text.count
                ))
                attempt = 0
                sendingRecordingID = nil
                await deliver(
                    raw: text, mode: mode, enhanced: enhanced,
                    id: id, uploadSeconds: seconds
                )
                return

            case .failure(let kind, let serverMessage):
                let failure = DictationFailure(kind: kind)
                let delay = UploadPlan.retryDelay(attempt: attemptNumber, failure: failure)
                trace(String(
                    format: "attempt %d/%d failed in %.0f ms: %@%@ — %@",
                    attemptNumber, maxAttempts, seconds * 1000, kind.label,
                    serverMessage.map { " server=“\($0)”" } ?? "",
                    delay.map { "retrying in \($0)" } ?? "no retry"
                ))
                guard let delay else {
                    attempt = 0
                    sendingRecordingID = nil
                    try? store.markFailed(id: id)
                    refreshRecordings()
                    fail(FailureInfo(
                        recordingID: id,
                        problem: .upload(kind: kind, serverMessage: serverMessage, attempts: attemptNumber)
                    ))
                    return
                }
                try? await Task.sleep(for: delay)
                attemptNumber += 1
            }
        }
    }

    // MARK: - Text delivery

    private func deliver(
        raw: String,
        mode: DictationMode,
        enhanced: Bool,
        id: UUID,
        uploadSeconds: TimeInterval
    ) async {
        guard let text = DictationText.deliverable(raw) else {
            // An empty answer must not wipe what the user already had copied.
            try? store.markFailed(id: id)
            refreshRecordings()
            trace("host answered 2xx with an empty body — clipboard left untouched")
            fail(FailureInfo(recordingID: id, problem: .noSpeech))
            return
        }

        let changeCount = AutoPaste.copyToPasteboard(text)
        try? store.markSent(id: id)
        refreshRecordings()
        trace("clipboard written (\(text.count) chars, pasteboard changeCount=\(changeCount))")

        let paste = await autoPaste(expected: pasteTargets[id])
        trace("delivery: \(paste.message)")

        lastDelivery = Delivery(
            recordingID: id,
            text: text,
            mode: mode,
            enhanced: enhanced,
            paste: paste,
            uploadSeconds: uploadSeconds
        )
        lastFailure = nil
        phase = .done
    }

    private func autoPaste(expected: String?) async -> PasteOutcome {
        guard settings.autoPasteEnabled else { return .clipboardOnly(.disabled) }
        // The target app needs a beat to see the new pasteboard contents.
        try? await Task.sleep(for: AutoPaste.pasteboardPropagationDelay)
        // Freshly, every time: the grant can be revoked between two dictations.
        guard AutoPaste.isTrusted else { return .clipboardOnly(.notTrusted) }
        let actual = AutoPaste.frontmostBundleID
        guard let expected, expected == actual else {
            return .clipboardOnly(.focusChanged(expected: expected, actual: actual))
        }
        guard AutoPaste.postCommandV() else { return .clipboardOnly(.postFailed) }
        return .pasted
    }

    // MARK: - Settings surface for the UI

    var hasToken: Bool { !tokenSource.read().isEmpty }

    func setToken(_ token: String) throws {
        try keychain.write(token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var loginItemState: LoginItem.State { LoginItem.state() }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        try LoginItem.setEnabled(enabled)
        settings.launchAtLoginEnabled = enabled
    }

    /// The Accessibility prompt, for the moment auto-typing is switched on.
    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        AutoPaste.requestTrust()
    }

    var isAccessibilityTrusted: Bool { AutoPaste.isTrusted }

    var microphoneAuthorization: AVAuthorizationStatus { AudioCaptureEngine.microphoneAuthorization }

    var inputDevices: [AudioInputDevice] { AudioDeviceList.inputDevices() }

    var recordingsDirectory: URL { store.directory }

    /// Puts the panel back to rest after a finished or failed dictation.
    func acknowledge() {
        guard phase == .done || phase == .failed else { return }
        phase = .idle
    }

    // MARK: - Internals

    private func resolveHost() throws -> HostConfig {
        try settings.hostConfig(token: tokenSource.read())
    }

    private func refreshRecordings() {
        recordings = store.recordings.reversed()
        hasFailedRecordings = store.hasFailedRecordings
        let live = Set(recordings.map(\.id))
        pasteTargets = pasteTargets.filter { live.contains($0.key) }
    }

    private func fail(_ info: FailureInfo) {
        lastFailure = info
        phase = .failed
        trace("FAILED: \(info.message)")
    }

    private func trace(_ message: String) {
        traceHandler?(message)
    }
}
