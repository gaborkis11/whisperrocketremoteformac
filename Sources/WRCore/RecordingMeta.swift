import Foundation

/// One entry of the recording ring, as persisted in `recordings.json`.
public struct RecordingMeta: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Status: String, Codable, Equatable, Sendable, CaseIterable {
        /// Captured, not sent yet — also the state a crashed capture is left in.
        case pending
        /// An upload attempt is in flight.
        case sending
        /// The host returned text. The entry stays in the ring.
        case sent
        /// Every allowed attempt failed; the audio is still on disk.
        case failed
    }

    public var id: UUID
    public var createdAt: Date
    public var durationSeconds: Double
    public var status: Status
    /// File name inside the store's directory — never a path.
    public var fileName: String

    public init(
        id: UUID,
        createdAt: Date,
        durationSeconds: Double = 0,
        status: Status = .pending,
        fileName: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.status = status
        self.fileName = fileName
    }
}
