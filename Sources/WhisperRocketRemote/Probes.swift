import AVFoundation
import Foundation
import WRCore

/// Command-line probes for the audio pipeline.
///
/// Two of them (`--devices`, `--synth-probe`) never touch the microphone, so
/// they can be run unattended — no TCC prompt can appear. `--record-probe` does
/// open the microphone and is meant to be run by a human at the keyboard.
enum Probes {
    /// Returns an exit code when a probe flag was present, `nil` when the app
    /// should boot normally.
    static func runIfRequested(_ arguments: [String] = CommandLine.arguments) -> Int32? {
        let flags = Set(arguments)
        if flags.contains("--devices") { return runDevices() }
        if flags.contains("--limits-probe") { return runLimits() }
        if let index = arguments.firstIndex(of: "--synth-probe") {
            return runSynth(arguments: Array(arguments.dropFirst(index + 1)))
        }
        if let index = arguments.firstIndex(of: "--record-probe") {
            return runRecord(arguments: Array(arguments.dropFirst(index + 1)))
        }
        return nil
    }

    // MARK: - --devices

    /// No permission needed: enumeration is not capture.
    private static func runDevices() -> Int32 {
        let devices = AudioDeviceList.inputDevices()
        log("devices", "\(devices.count) input device(s)")
        for device in devices {
            let marker = device.isSystemDefault ? "*" : " "
            log("devices", "\(marker) \(device.name)")
            log("devices", "    uid=\(device.uid)")
            log("devices", "    id=\(device.deviceID) inputChannels=\(device.inputChannelCount) "
                + "nominalRate=\(Int(device.nominalSampleRate)) default=\(device.isSystemDefault)")
        }
        switch AudioDeviceList.resolve(.systemDefault) {
        case .systemDefault(let device):
            log("devices", "resolve(.systemDefault) -> \(device?.name ?? "<none>")")
        default:
            break
        }
        if let first = devices.first {
            log("devices", "resolve(.uid(\(first.uid))) -> \(describe(AudioDeviceList.resolve(.uid(first.uid))))")
        }
        log("devices", "resolve(.uid(\"does-not-exist\")) -> \(describe(AudioDeviceList.resolve(.uid("does-not-exist"))))")
        log("devices", "microphone TCC status: \(AudioCaptureEngine.describe(AudioCaptureEngine.microphoneAuthorization))")
        return 0
    }

    private static func describe(_ resolution: AudioInputResolution) -> String {
        switch resolution {
        case .systemDefault(let device): "systemDefault(\(device?.name ?? "<none>"))"
        case .device(let device): "device(\(device.name))"
        case .missing(let uid, let fallback): "missing(\(uid), fallback: \(fallback?.name ?? "<none>"))"
        }
    }

    // MARK: - --synth-probe

    /// `--synth-probe <out.m4a> [seconds] [24k-mono|48k-stereo]`
    ///
    /// Pushes generated 440 Hz sine buffers through the *same* writer the live
    /// tap uses. That is what closes the AVAudioFile/AAC format risk without a
    /// microphone: if the converter output and the file's processing format
    /// disagreed, this would fail here.
    private static func runSynth(arguments: [String]) -> Int32 {
        let (positional, _) = parse(arguments, valueFlags: [])
        // White noise instead of a sine: AAC is variable-rate, and a pure tone
        // compresses to nothing. `--noise` gives the worst-case file size.
        let useNoise = arguments.contains("--noise")
        guard let path = positional.first else {
            log("synth-probe", "usage: --synth-probe <out.m4a> [seconds] [24k-mono|48k-stereo]")
            return 2
        }
        let url = URL(fileURLWithPath: path)
        let seconds = positional.count > 1 ? (Double(positional[1]) ?? 3) : 3
        let preset = positional.count > 2 ? positional[2] : "24k-mono"

        let sampleRate: Double
        let channels: AVAudioChannelCount
        switch preset {
        case "48k-stereo":
            sampleRate = 48_000
            channels = 2
        case "24k-mono":
            sampleRate = 24_000
            channels = 1
        default:
            log("synth-probe", "unknown source preset “\(preset)” (use 24k-mono or 48k-stereo)")
            return 2
        }

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            log("synth-probe", "could not build the source format")
            return 1
        }

        log("synth-probe", "source (imitating the live tap): \(sourceFormat) "
            + "signal=\(useNoise ? "white noise" : "440 Hz sine") seconds=\(seconds)")
        try? FileManager.default.removeItem(at: url)

        let writer: AudioSampleWriter
        do {
            writer = try AudioSampleWriter(url: url, sourceFormat: sourceFormat)
        } catch {
            log("synth-probe", "FAILED to open the writer: \(error.message)")
            return 1
        }
        log("synth-probe", "file processingFormat == converter output: \(writer.outputFormat)")

        let monitor = AudioLevelMonitor()
        let chunk: AVAudioFrameCount = 2_048
        let totalFrames = Int64(seconds * sampleRate)
        var produced: Int64 = 0
        var phase: Double = 0
        let increment = 2 * Double.pi * 440 / sampleRate
        var chunkIndex = 0
        var samples: [(TimeInterval, Float, Float)] = []

        while produced < totalFrames {
            let frames = AVAudioFrameCount(min(Int64(chunk), totalFrames - produced))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames),
                  let channelData = buffer.floatChannelData else {
                log("synth-probe", "buffer allocation failed")
                writer.abort()
                return 1
            }
            buffer.frameLength = frames
            // Amplitude sweeps from -40 dBFS up to -6 dBFS so the meter has
            // something to actually track.
            let progress = Double(produced) / Double(max(totalFrames, 1))
            let amplitude = Float(0.01 + 0.49 * progress)
            for frame in 0..<Int(frames) {
                let value = useNoise
                    ? amplitude * Float.random(in: -1...1)
                    : amplitude * Float(sin(phase))
                phase += increment
                if phase > 2 * .pi { phase -= 2 * .pi }
                for channel in 0..<Int(channels) {
                    channelData[channel][frame] = value
                }
            }

            let measurement = AudioLevelMath.measure(buffer)
            let elapsed = Double(produced + Int64(frames)) / sampleRate
            monitor.ingest(AudioLevelSample(rms: measurement.rms, peak: measurement.peak, elapsed: elapsed))

            do {
                try writer.write(buffer)
            } catch {
                log("synth-probe", "write failed: \(error.message)")
                writer.abort()
                return 1
            }
            produced += Int64(frames)

            if chunkIndex % 8 == 0 {
                // Let the main actor drain so the monitor really is exercised.
                RunLoop.current.run(until: Date().addingTimeInterval(0.002))
                samples.append((elapsed, measurement.rms, measurement.peak))
            }
            chunkIndex += 1
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        for (elapsed, rms, peak) in samples.suffix(4) {
            log("synth-probe", String(
                format: "level t=%.2fs rms=%.4f (%.1f dBFS) peak=%.4f",
                elapsed, rms, AudioLevelMath.decibels(linear: rms), peak
            ))
        }
        log("synth-probe", String(
            format: "monitor after drain: level=%.3f peak=%.3f elapsed=%.2fs active=%@",
            monitor.level, monitor.peak, monitor.elapsed, monitor.isActive ? "true" : "false"
        ))

        let result: AudioRecordingFile
        do {
            result = try writer.finish()
        } catch {
            log("synth-probe", "FAILED to finish: \(error.message)")
            return 1
        }
        report(result, tag: "synth-probe")
        return 0
    }

    // MARK: - --limits-probe

    /// Proves the 4:30 countdown and the 5:00 ceiling offline, by feeding the
    /// tracker the frame counts a 24 kHz microphone would deliver.
    private static func runLimits() -> Int32 {
        let sampleRate = 24_000.0
        let bufferFrames: Int64 = 2_048
        var tracker = RecordingLimitTracker(limits: .default)
        var countdownEvents: [Int] = []
        var limitElapsed: TimeInterval?
        var totalAccepted: Int64 = 0
        var offered: Int64 = 0

        // Six minutes of buffers: one minute past the ceiling on purpose.
        while offered < Int64(360 * sampleRate) {
            let admission = tracker.admit(frames: bufferFrames, sampleRate: sampleRate)
            offered += bufferFrames
            totalAccepted += admission.acceptedFrames
            for event in admission.events {
                switch event {
                case .countdown(let remaining):
                    countdownEvents.append(remaining)
                case .limitReached:
                    limitElapsed = tracker.elapsed
                }
            }
        }

        log("limits-probe", "offered \(offered) frames (\(offered / Int64(sampleRate)) s), "
            + "accepted \(totalAccepted) frames (\(String(format: "%.3f", Double(totalAccepted) / sampleRate)) s)")
        log("limits-probe", "first countdown at remaining=\(countdownEvents.first.map(String.init) ?? "<none>") s, "
            + "last=\(countdownEvents.last.map(String.init) ?? "<none>") s, count=\(countdownEvents.count)")
        log("limits-probe", "countdown ladder: \(countdownEvents.prefix(4).map(String.init).joined(separator: ",")) … "
            + "\(countdownEvents.suffix(3).map(String.init).joined(separator: ","))")
        log("limits-probe", "limitReached at elapsed=\(limitElapsed.map { String(format: "%.3f s", $0) } ?? "<never>") "
            + "(expected 300.000 s, fired once)")
        let ok = limitElapsed != nil
            && abs((limitElapsed ?? 0) - 300) < 0.001
            && countdownEvents.first == 30
            && countdownEvents.last == 1
            && countdownEvents.count == 30
            && totalAccepted == Int64(300 * sampleRate)
        log("limits-probe", ok ? "PASS" : "FAIL")
        return ok ? 0 : 1
    }

    // MARK: - --record-probe

    /// `--record-probe <seconds> <out.m4a> [--device <uid>] [--limit <seconds>]`
    ///
    /// Live microphone capture. Never run this unattended: the first run raises
    /// the TCC prompt, and an unanswered prompt kills `engine.start()`.
    /// `--limit` shortens the 5-minute ceiling so the countdown and the
    /// auto-stop path can be seen in seconds instead of minutes.
    private static func runRecord(arguments: [String]) -> Int32 {
        let (positional, values) = parse(arguments, valueFlags: ["--device", "--limit"])
        guard positional.count >= 2, let seconds = Double(positional[0]) else {
            log("record-probe", "usage: --record-probe <seconds> <out.m4a> [--device <uid>] [--limit <seconds>]")
            return 2
        }
        let url = URL(fileURLWithPath: positional[1])
        let requestedUID = values["--device"]
        let customLimit = values["--limit"].flatMap(Double.init)

        let selection = AudioInputSelection(storedUID: requestedUID)
        let resolution = AudioDeviceList.resolve(selection)
        log("record-probe", "selection=\(selection) resolution=\(describe(resolution))")
        if case .missing(let uid, _) = resolution {
            log("record-probe", "WARNING: saved device \(uid) is gone; recording from the system default")
        }
        log("record-probe", "microphone TCC status: \(AudioCaptureEngine.describe(AudioCaptureEngine.microphoneAuthorization))")

        let limits: RecordingLimits = customLimit.map {
            RecordingLimits(maxDuration: $0, countdownThreshold: min(30, max(1, $0 / 2)))
        } ?? .default
        log("record-probe", "limits: maxDuration=\(limits.maxDuration)s countdownThreshold=\(limits.countdownThreshold)s")

        let engine = AudioCaptureEngine(limits: limits)
        let monitor = AudioLevelMonitor()
        let session = RecordProbeSession()

        let callbacks = AudioCaptureEngine.Callbacks(
            onLevel: monitor.levelHandler(),
            onCountdown: { remaining in
                Task { @MainActor in log("record-probe", "countdown: \(remaining) s left") }
            },
            onLimitReached: {
                Task { @MainActor in
                    log("record-probe", "LIMIT REACHED -> the caller stops, exactly like a manual stop")
                    session.shouldStop = true
                }
            },
            onFailure: { error in
                Task { @MainActor in log("record-probe", "FAILURE during capture: \(error.message)") }
            }
        )

        try? FileManager.default.removeItem(at: url)
        do {
            try engine.start(writingTo: url, device: resolution.deviceToUse, callbacks: callbacks)
        } catch {
            log("record-probe", "start FAILED: \(error.message)")
            return 1
        }
        // Asked, not assumed: this is the format the hardware really delivers.
        log("record-probe", "native tap format: \(engine.inputFormat?.description ?? "<none>")")
        log("record-probe", "recording… speak now")

        let deadline = Date().addingTimeInterval(seconds)
        var nextPrint = Date()
        while !session.shouldStop, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if Date() >= nextPrint {
                nextPrint = Date().addingTimeInterval(0.25)
                let filled = Int((monitor.level * 30).rounded())
                let bar = String(repeating: "#", count: filled) + String(repeating: ".", count: 30 - filled)
                log("record-probe", String(
                    format: "t=%5.2fs [%@] level=%.3f peak=%.3f",
                    monitor.elapsed, bar, monitor.level, monitor.peak
                ))
            }
        }

        do {
            let result = try engine.stop()
            report(result, tag: "record-probe")
            log("record-probe", "engine.isRecording after stop: \(engine.isRecording)")
            return 0
        } catch {
            log("record-probe", "stop FAILED: \(error.message)")
            return 1
        }
    }

    @MainActor
    private final class RecordProbeSession {
        var shouldStop = false
    }

    // MARK: - Shared output

    private static func report(_ file: AudioRecordingFile, tag: String) {
        let kbps = file.duration > 0 ? Double(file.byteCount) * 8 / file.duration / 1_000 : 0
        log(tag, "wrote \(file.url.path)")
        log(tag, String(
            format: "  format=%@ sampleRate=%.0f channels=%d duration=%.3fs bytes=%d (~%.1f kbit/s)",
            file.formatDescription, file.sampleRate, file.channelCount, file.duration, file.byteCount, kbps
        ))
        // The .m4a carries a fixed ~24 kB header, so short files look bitrate-heavy.
        if file.duration > 0 {
            log(tag, String(
                format: "  extrapolated 5:00 size ≈ %.2f MB (host limit is 25 MB)",
                Double(file.byteCount) / file.duration * 300 / 1_048_576
            ))
        }
        let ok = file.sampleRate == AudioRecordingFormat.sampleRate
            && file.channelCount == Int(AudioRecordingFormat.channelCount)
            && file.formatID == kAudioFormatMPEG4AAC
        log(tag, ok ? "  PASS: 16 kHz / mono / AAC" : "  FAIL: unexpected output format")
    }

    /// Splits `--flag value` pairs out of the trailing arguments so the
    /// positional ones keep their meaning wherever the flags are placed.
    private static func parse(
        _ arguments: [String],
        valueFlags: Set<String>
    ) -> (positional: [String], values: [String: String]) {
        var positional: [String] = []
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            if token.hasPrefix("--") {
                if valueFlags.contains(token), index + 1 < arguments.count,
                   !arguments[index + 1].hasPrefix("--") {
                    values[token] = arguments[index + 1]
                    index += 2
                    continue
                }
                index += 1
                continue
            }
            positional.append(token)
            index += 1
        }
        return (positional, values)
    }

    private static func log(_ tag: String, _ message: String) {
        print("[\(tag)] \(message)")
        fflush(stdout)
    }
}
