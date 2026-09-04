import AVFoundation
import Foundation

/// The on-disk recording format. One definition, used by the live tap and by
/// the offline synth probe alike, so `--synth-probe` really does prove what the
/// microphone path will produce.
nonisolated enum AudioRecordingFormat {
    static let sampleRate: Double = 16_000
    static let channelCount: AVAudioChannelCount = 1
    /// 48 kbit/s AAC-LC at 16 kHz mono: 5 minutes ≈ 1.8 MB, far under the
    /// host's 25 MB cap, and well above what 16 kHz speech needs.
    static let bitRate = 48_000
    static let fileExtension = "m4a"

    static func fileSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(channelCount),
            AVEncoderBitRateKey: bitRate,
        ]
    }
}

/// What a finished recording turned out to be. Read back off disk rather than
/// predicted, so a caller that gets this value knows the file is decodable.
nonisolated struct AudioRecordingFile: Sendable {
    let url: URL
    let duration: TimeInterval
    let byteCount: Int
    let sampleRate: Double
    let channelCount: Int
    let formatID: AudioFormatID

    var formatDescription: String {
        let id = formatID
        let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((id >> $0) & 0xFF))) }
        return String(chars)
    }
}

/// Converts native capture buffers to 16 kHz mono and encodes them into an AAC
/// `.m4a`.
///
/// The one rule that matters here: the converter's output format *is*
/// `AVAudioFile.processingFormat`, taken from the file itself rather than
/// rebuilt by hand. That is the fix for the known AAC/AVAudioFile format
/// mismatch risk — there is no second format description that could drift.
///
/// Not internally synchronised: the owner (`AudioCaptureEngine`) serialises all
/// access, and the probes use it from a single thread.
nonisolated final class AudioSampleWriter {
    let sourceFormat: AVAudioFormat
    /// Equal to the file's `processingFormat` by construction.
    let outputFormat: AVAudioFormat

    private let url: URL
    private var file: AVAudioFile?
    private let converter: AVAudioConverter
    /// Reused across buffers: the tap fires ~23×/s and the audio thread should
    /// not be allocating on every one of them.
    private var scratch: AVAudioPCMBuffer?
    private var outputFrames: AVAudioFramePosition = 0
    private var didReceiveInput = false
    private var isFinished = false

    /// Frames handed to the encoder so far, in the 16 kHz output timebase.
    var framesWritten: AVAudioFramePosition { outputFrames }

    init(url: URL, sourceFormat: AVAudioFormat) throws(AudioCaptureError) {
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw .invalidInputFormat(description: sourceFormat.description)
        }
        self.url = url
        self.sourceFormat = sourceFormat

        // Directory first: AVAudioFile will not create intermediate folders.
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .fileCreationFailed(url: url, underlying: String(describing: error))
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: url,
                settings: AudioRecordingFormat.fileSettings(),
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw .fileCreationFailed(url: url, underlying: String(describing: error))
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: file.processingFormat) else {
            // Remove the file we just opened; nothing half-written survives.
            try? FileManager.default.removeItem(at: url)
            throw .converterUnavailable(
                source: sourceFormat.description,
                destination: file.processingFormat.description
            )
        }
        self.file = file
        self.outputFormat = file.processingFormat
        // Multi-channel inputs (a 4-in interface, an aggregate device) must fold
        // down to mono rather than have channels dropped.
        converter.downmix = true
        converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        self.converter = converter
    }

    /// Converts and appends one capture buffer. Returns the number of output
    /// frames produced (the resampler buffers, so this is not `frames * ratio`).
    @discardableResult
    func write(_ buffer: AVAudioPCMBuffer) throws(AudioCaptureError) -> AVAudioFrameCount {
        guard let file, !isFinished else { throw .writerClosed }
        guard buffer.frameLength > 0 else { return 0 }

        let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
        // Headroom for the resampler's own latency on top of the naive estimate.
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1_024
        guard let output = outputBuffer(capacity: capacity) else {
            throw .conversionFailed(reason: "could not allocate a \(capacity)-frame output buffer")
        }

        let source = SingleBufferSource(buffer)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            source.next(inputStatus)
        }

        switch status {
        case .haveData, .inputRanDry:
            break
        case .endOfStream:
            break
        case .error:
            throw .conversionFailed(reason: conversionError.map(String.init(describing:)) ?? "unknown")
        @unknown default:
            throw .conversionFailed(reason: "unknown converter status \(status.rawValue)")
        }

        didReceiveInput = true
        guard output.frameLength > 0 else { return 0 }
        do {
            try file.write(from: output)
        } catch {
            throw .writeFailed(underlying: String(describing: error))
        }
        outputFrames += AVAudioFramePosition(output.frameLength)
        return output.frameLength
    }

    /// Flushes the resampler tail, closes the file, and reads back what landed
    /// on disk. Safe to call exactly once.
    func finish() throws(AudioCaptureError) -> AudioRecordingFile {
        guard file != nil, !isFinished else { throw .writerClosed }
        isFinished = true
        drain()
        // AVAudioFile has no close(); dropping the last reference is what
        // finalises the MPEG-4 container. Note there must be no other strong
        // reference alive at this point — holding one in a local made the
        // read-back below fail on a still-unfinalised file.
        file = nil
        return try inspectFinishedFile()
    }

    /// Give up: close the file and remove the partial recording. Used on the
    /// failure paths so a half-open AAC container never survives.
    func abort() {
        isFinished = true
        file = nil
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    /// `AVAudioConverterInputBlock` is declared `@Sendable`, but the converter
    /// only ever calls it synchronously, on this thread, from inside
    /// `convert(to:error:withInputFrom:)`. This box states that instead of
    /// weakening `AVAudioPCMBuffer`'s checking everywhere else.
    private final class SingleBufferSource: @unchecked Sendable {
        private var buffer: AVAudioPCMBuffer?

        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

        func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
            guard let buffer else {
                status.pointee = .noDataNow
                return nil
            }
            self.buffer = nil
            status.pointee = .haveData
            return buffer
        }
    }

    private func outputBuffer(capacity: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        if let scratch, scratch.frameCapacity >= capacity {
            scratch.frameLength = 0
            return scratch
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        scratch = buffer
        return buffer
    }

    /// Deliberately reaches for `self.file` rather than taking it as a
    /// parameter: the caller must not keep a strong reference across `finish()`.
    private func drain() {
        guard didReceiveInput, let file else { return }
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else { return }
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            inputStatus.pointee = .endOfStream
            return nil
        }
        guard status != .error, output.frameLength > 0 else { return }
        if (try? file.write(from: output)) != nil {
            outputFrames += AVAudioFramePosition(output.frameLength)
        }
    }

    private func inspectFinishedFile() throws(AudioCaptureError) -> AudioRecordingFile {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attributes?[.size] as? Int) ?? 0

        let readBack: AVAudioFile
        do {
            readBack = try AVAudioFile(forReading: url)
        } catch {
            throw .unreadableRecording(url: url, underlying: String(describing: error))
        }
        let asbd = readBack.fileFormat.streamDescription.pointee
        let sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : AudioRecordingFormat.sampleRate
        return AudioRecordingFile(
            url: url,
            duration: Double(readBack.length) / sampleRate,
            byteCount: byteCount,
            sampleRate: sampleRate,
            channelCount: Int(asbd.mChannelsPerFrame),
            formatID: asbd.mFormatID
        )
    }
}
