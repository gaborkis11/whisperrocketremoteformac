import Foundation

/// The file operations `RecordingStore` needs, so the ring can be exercised
/// against a temp directory (or anything else) without reaching for globals.
public protocol RecordingFileSystem: Sendable {
    func createDirectory(at url: URL) throws
    func fileExists(at url: URL) -> Bool
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func removeItem(at url: URL) throws
    func readData(at url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
}

public struct DiskFileSystem: RecordingFileSystem {
    public init() {}

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

public enum RecordingStoreError: Error, Equatable, Sendable {
    case unknownRecording(UUID)
}

/// A fixed-size ring of recordings on disk plus its JSON index.
///
/// The audio is written *directly* into the slot handed out by ``reserve(id:createdAt:)``,
/// so "every recording is on disk" is structural: there is no separate save
/// step that could be skipped when something goes wrong. A sent recording
/// keeps its slot — only age evicts an entry.
///
/// Not thread-safe: the app owns one instance on the main actor.
public final class RecordingStore {
    public static let indexFileName = "recordings.json"

    public let directory: URL
    public let capacity: Int
    public let fileExtension: String

    private let fileSystem: RecordingFileSystem
    /// Insertion order — index 0 is the oldest, and the next to be evicted.
    private var items: [RecordingMeta] = []

    /// Everything in the ring, oldest first. Reverse it for a newest-first list.
    public var recordings: [RecordingMeta] { items }

    /// True while any entry needs the user's attention (the status-item badge).
    public var hasFailedRecordings: Bool { items.contains { $0.status == .failed } }

    public init(
        directory: URL,
        capacity: Int = 3,
        fileExtension: String = "m4a",
        fileSystem: RecordingFileSystem = DiskFileSystem()
    ) throws {
        precondition(capacity > 0, "a ring with no slots cannot hold a recording")
        self.directory = directory
        self.capacity = capacity
        self.fileExtension = fileExtension
        self.fileSystem = fileSystem

        try fileSystem.createDirectory(at: directory)
        try load()
    }

    /// The default location: `~/Library/Application Support/<appName>/Recordings`.
    public static func defaultDirectory(appName: String = "WhisperRocket Remote") throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    // MARK: - Reading

    public func recording(id: UUID) -> RecordingMeta? {
        items.first { $0.id == id }
    }

    public func fileURL(for meta: RecordingMeta) -> URL {
        directory.appendingPathComponent(meta.fileName, isDirectory: false)
    }

    public func fileURL(id: UUID) -> URL? {
        recording(id: id).map(fileURL(for:))
    }

    // MARK: - Writing

    /// A slot in the ring. The recorder writes the audio straight to `fileURL`.
    public struct Reservation: Equatable, Sendable {
        public let meta: RecordingMeta
        public let fileURL: URL
    }

    /// Makes room (evicting the oldest entries and their audio) and hands out a
    /// `pending` slot.
    public func reserve(id: UUID = UUID(), createdAt: Date = Date()) throws -> Reservation {
        while items.count >= capacity {
            try evictOldest()
        }
        let meta = RecordingMeta(
            id: id,
            // Whole seconds, so what comes back out of `recordings.json` is
            // exactly what went in — the index stays readable *and* lossless.
            createdAt: Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down)),
            status: .pending,
            fileName: "\(id.uuidString).\(fileExtension)"
        )
        items.append(meta)
        try persist()
        return Reservation(meta: meta, fileURL: fileURL(for: meta))
    }

    public func updateStatus(_ status: RecordingMeta.Status, id: UUID) throws {
        try mutate(id: id) { $0.status = status }
    }

    public func markSending(id: UUID) throws { try updateStatus(.sending, id: id) }
    public func markSent(id: UUID) throws { try updateStatus(.sent, id: id) }
    public func markFailed(id: UUID) throws { try updateStatus(.failed, id: id) }
    public func markPending(id: UUID) throws { try updateStatus(.pending, id: id) }

    /// The capture only knows its length once it stops.
    public func updateDuration(_ seconds: Double, id: UUID) throws {
        try mutate(id: id) { $0.durationSeconds = seconds }
    }

    private func mutate(id: UUID, _ body: (inout RecordingMeta) -> Void) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw RecordingStoreError.unknownRecording(id)
        }
        body(&items[index])
        try persist()
    }

    // MARK: - Loading, recovery and consistency

    private func load() throws {
        // Insertion order *is* ring order, so the file's order is authoritative;
        // re-sorting by `createdAt` would only add a way for a clock change or a
        // second-resolution timestamp tie to evict the wrong recording.
        let decoded = decodeIndex()
        items = decoded ?? []
        var changed = false

        // A `sending` entry on disk means the app died mid-upload: nothing is
        // in flight any more, so the user must be able to resend it.
        for index in items.indices where items[index].status == .sending {
            items[index].status = .failed
            changed = true
        }

        // An entry whose audio is gone can never be resent — and a crash
        // between reserving a slot and the first captured frame leaves exactly
        // that. Drop it instead of showing an unusable row.
        let withAudio = items.filter { fileSystem.fileExists(at: fileURL(for: $0)) }
        if withAudio.count != items.count {
            items = withAudio
            changed = true
        }

        if items.count > capacity {
            items = Array(items.suffix(capacity))
            changed = true
        }

        // Only sweep when the index was actually readable. Deleting audio we
        // can no longer describe, in the very moment the description was lost,
        // is the one mistake this store must not make; the files survive the
        // launch and go on the next one, once the index is sound again.
        if decoded != nil {
            try removeOrphanFiles()
        }
        if changed {
            try persist()
        }
    }

    /// `nil` when there is no index to trust — missing, unreadable or corrupt.
    private func decodeIndex() -> [RecordingMeta]? {
        let url = indexURL
        guard fileSystem.fileExists(at: url), let data = try? fileSystem.readData(at: url) else {
            return nil
        }
        return try? Self.decoder.decode([RecordingMeta].self, from: data)
    }

    /// Deletes audio files no entry points at. Only files named after a UUID
    /// are touched — nothing else in the directory is ours to remove.
    private func removeOrphanFiles() throws {
        let known = Set(items.map(\.fileName))
        for url in try fileSystem.contentsOfDirectory(at: directory) {
            let name = url.lastPathComponent
            guard !known.contains(name),
                  UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
            else { continue }
            try fileSystem.removeItem(at: url)
        }
    }

    private func evictOldest() throws {
        guard !items.isEmpty else { return }
        let victim = items.removeFirst()
        let url = fileURL(for: victim)
        if fileSystem.fileExists(at: url) {
            try fileSystem.removeItem(at: url)
        }
    }

    // MARK: - Persistence

    private var indexURL: URL {
        directory.appendingPathComponent(Self.indexFileName, isDirectory: false)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private func persist() throws {
        try fileSystem.write(Self.encoder.encode(items), to: indexURL)
    }
}
