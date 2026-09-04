import AppKit
import Foundation
import WRCore
import WRNetwork

/// `--flow-probe <seconds> --log <file> [--host <h[:port]>] [--token <t>]`
/// `                       [--device <uid>] [--limit <seconds>] [--resend]`
///
/// Drives the *real* `DictationController` end to end — reserve, capture,
/// stop, upload, deliver — with every step timestamped into a log file. It
/// exists because the whole chain is otherwise only reachable through a hotkey
/// and a human voice, and the failure paths (401, unreachable host, retry
/// timing) need machine-checkable evidence.
///
/// It runs inside the app bundle, from `applicationDidFinishLaunching`, for two
/// reasons: the microphone TCC grant belongs to the bundle, and the capture
/// engine needs a live run loop.
enum FlowProbe {
    struct Request {
        var seconds: Double
        var logURL: URL?
        var host: String?
        var token: String?
        var deviceUID: String?
        /// After the flow ends, re-send the newest recording once — the panel's
        /// resend button, with a fresh attempt counter.
        var resend = false
        /// Shrinks the capture ceiling so the auto-stop, its countdown and its
        /// stop click can be observed in seconds instead of five minutes. The
        /// path taken is the production one; only the number moves.
        var limitSeconds: Double?
    }

    /// Exit codes, so a shell can tell the three outcomes apart.
    enum Exit: Int32 {
        /// The dictation came back and the text was delivered.
        case delivered = 0
        /// The harness itself could not run (no ring, no microphone, bad usage).
        case harnessFailure = 1
        case usage = 2
        /// The flow ran to completion and ended in a failure — which is the
        /// *expected* result for the 401 and unreachable-host runs.
        case flowFailed = 3
    }

    static func request(from arguments: [String]) -> Request? {
        guard let index = arguments.firstIndex(of: "--flow-probe") else { return nil }
        let rest = Array(arguments.dropFirst(index + 1))
        var request = Request(seconds: 3)
        var positional: [String] = []
        var cursor = 0
        while cursor < rest.count {
            let token = rest[cursor]
            guard token.hasPrefix("--") else {
                positional.append(token)
                cursor += 1
                continue
            }
            if token == "--resend" {
                request.resend = true
                cursor += 1
                continue
            }
            let value = cursor + 1 < rest.count && !rest[cursor + 1].hasPrefix("--") ? rest[cursor + 1] : nil
            switch token {
            case "--log": request.logURL = value.map { URL(fileURLWithPath: $0) }
            case "--host": request.host = value
            case "--token": request.token = value
            case "--device": request.deviceUID = value
            case "--limit": request.limitSeconds = value.flatMap(Double.init)
            default: break
            }
            cursor += value == nil ? 1 : 2
        }
        if let first = positional.first, let seconds = Double(first) {
            request.seconds = seconds
        }
        return request
    }

    /// Starts the probe and terminates the process when it is done.
    static func start(_ request: Request) {
        Task { @MainActor in
            let code = await run(request)
            exit(code.rawValue)
        }
    }

    static func run(_ request: Request) async -> Exit {
        let log = FlowLog(url: request.logURL)
        log.line("flow-probe start: seconds=\(request.seconds) bundle=\(Bundle.main.bundlePath)")
        log.line("microphone TCC: \(AudioCaptureEngine.describe(AudioCaptureEngine.microphoneAuthorization))")
        log.line("accessibility trusted: \(AutoPaste.isTrusted)")
        log.line("login item: \(LoginItem.state()) (in /Applications: \(LoginItem.isInstalledInApplications))")

        // A scratch defaults suite, seeded from the real one: a probe run must
        // not be able to rewrite the user's host, device or switches.
        let suiteName = "com.gaborkis.WhisperRocketRemote.flow-probe"
        let scratch = UserDefaults(suiteName: suiteName) ?? .standard
        scratch.removePersistentDomain(forName: suiteName)
        defer {
            scratch.removePersistentDomain(forName: suiteName)
            // The probe calls exit() the moment this returns, so cfprefsd has
            // to be pushed rather than left to flush on its own.
            scratch.synchronize()
        }

        let real = Settings()
        let settings = Settings(defaults: scratch)
        settings.host = real.host
        settings.port = real.port
        settings.inputDeviceUID = request.deviceUID ?? real.inputDeviceUID
        // Never synthesise ⌘V into whatever happens to be frontmost during an
        // unattended run.
        settings.autoPasteEnabled = false
        settings.soundsEnabled = true

        if let hostArgument = request.host {
            let (host, port) = splitHostPort(hostArgument)
            settings.host = host
            if let port { settings.port = port }
        }

        let token = request.token ?? ((try? KeychainStore().read()) ?? nil) ?? ""
        log.line("host=\(settings.host):\(settings.port) "
            + "token=\(token.isEmpty ? "<none>" : "<\(token.count) chars>") "
            + "device=\(settings.inputDeviceUID ?? "<system default>")")

        let store: RecordingStore
        do {
            store = try RecordingStore(directory: RecordingStore.defaultDirectory())
        } catch {
            log.line("HARNESS FAILURE: could not open the recording store: \(error)")
            return .harnessFailure
        }
        log.line("ring: \(store.directory.path) capacity=\(store.capacity) entries=\(store.recordings.count)")

        let limits = request.limitSeconds.map {
            RecordingLimits(maxDuration: $0, countdownThreshold: min(30, max(1, $0 / 2)))
        } ?? .default
        log.line("limits: maxDuration=\(limits.maxDuration)s countdownThreshold=\(limits.countdownThreshold)s")

        let controller = DictationController(
            settings: settings,
            store: store,
            tokenSource: .literal(token),
            engine: AudioCaptureEngine(limits: limits)
        )
        controller.traceHandler = { message in log.line(message) }
        log.line("sounds loaded: \(controller.soundPlayer.isLoaded) "
            + "missing=\(controller.soundPlayer.missingCues.map(\.rawValue))")

        controller.startRecording()
        guard controller.isRecording else {
            log.line("HARNESS FAILURE: recording did not start — \(controller.lastFailure?.message ?? "unknown")")
            return .harnessFailure
        }

        // The room's silence is a perfectly good signal for the failure paths.
        try? await Task.sleep(for: .seconds(request.seconds))
        log.line(String(
            format: "meter before stop: level=%.3f peak=%.3f elapsed=%.2f s",
            controller.levelMonitor.level, controller.levelMonitor.peak, controller.levelMonitor.elapsed
        ))
        log.line("hostReachable=\(String(describing: controller.hostReachable)) "
            + "banner=\(controller.storedModeBanner ?? "<none>")")

        if request.limitSeconds != nil {
            // Nobody stops this one: the ceiling has to do it, on its own.
            log.line("waiting for the ceiling to stop the recording by itself…")
            let ceilingDeadline = Date().addingTimeInterval(60)
            while controller.isRecording, Date() < ceilingDeadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            log.line("after the ceiling: isRecording=\(controller.isRecording) "
                + "phase=\(controller.phase) countdown=\(String(describing: controller.countdown))")
        } else {
            controller.stopRecording()
        }

        // Long enough for three attempts plus the 2 s + 5 s backoff and a slow
        // five-minute transcription.
        let deadline = Date().addingTimeInterval(400)
        while controller.isBusy, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if controller.isBusy {
            log.line("HARNESS FAILURE: the flow was still busy after 400 s")
            return .harnessFailure
        }

        if request.resend, let newest = controller.recordings.first {
            log.line("--- manual resend of \(newest.id) (status was \(newest.status.rawValue)) ---")
            controller.resend(id: newest.id)
            let resendDeadline = Date().addingTimeInterval(400)
            while controller.isBusy, Date() < resendDeadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }

        log.line("--- result ---")
        log.line("phase=\(controller.phase)")
        if let delivery = controller.lastDelivery {
            log.line(String(
                format: "delivered %d chars in %.0f ms (mode=%@ enhanced=%@)",
                delivery.text.count, delivery.uploadSeconds * 1000,
                delivery.mode.rawValue, String(describing: delivery.enhanced)
            ))
            log.line("paste: \(delivery.paste.message)")
            log.line("text: \(delivery.text.prefix(400))")
        }
        if let failure = controller.lastFailure {
            log.line("failure: \(failure.message)")
        }
        log.line("hasFailedRecordings=\(controller.hasFailedRecordings)")
        for meta in controller.recordings {
            log.line(String(
                format: "  ring entry %@ status=%@ duration=%.3f s file=%@",
                meta.id.uuidString, meta.status.rawValue, meta.durationSeconds, meta.fileName
            ))
        }
        let indexURL = store.directory.appendingPathComponent(RecordingStore.indexFileName)
        log.line("index: \(indexURL.path) "
            + "(\((try? Data(contentsOf: indexURL))?.count ?? -1) bytes)")
        log.line("flow-probe done")

        return controller.phase == .done ? .delivered : .flowFailed
    }

    /// `100.64.0.42:8771` → ("100.64.0.42", 8771). A bare host keeps the
    /// configured port. IPv6 literals must arrive bracketed, which is also what
    /// `HostConfig` requires.
    static func splitHostPort(_ text: String) -> (host: String, port: Int?) {
        guard let separator = text.lastIndex(of: ":") else { return (text, nil) }
        let hostPart = String(text[text.startIndex..<separator])
        let portPart = String(text[text.index(after: separator)...])
        guard !hostPart.isEmpty, let port = Int(portPart),
              // An IPv6 literal is all colons; only a bracketed one has a port.
              !hostPart.contains(":") || hostPart.hasSuffix("]")
        else { return (text, nil) }
        return (hostPart, port)
    }
}

/// Append-only, line-buffered log. Flushed per line so a crash still leaves the
/// steps that got that far, and mirrored to stdout for terminal runs (`open`
/// swallows stdout, which is exactly why `--log` exists).
final class FlowLog {
    private let handle: FileHandle?
    private let started = Date()

    init(url: URL?) {
        guard let url else {
            handle = nil
            return
        }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    func line(_ text: String) {
        let stamp = String(format: "[%7.3f] ", Date().timeIntervalSince(started))
        let output = stamp + text + "\n"
        print(output, terminator: "")
        fflush(stdout)
        guard let handle, let data = output.data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
    }
}
