import Foundation
import Testing
@testable import WRCore

@Suite struct RecordingStoreTests {
    /// A throwaway directory per test — the real `DiskFileSystem` runs against
    /// it, so what the tests observe is what the app will do on disk.
    private func makeDirectory() throws -> URL {
        let url = URL.temporaryDirectory
            .appendingPathComponent("RecordingStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Stands in for the audio the capture engine writes into the slot.
    @discardableResult
    private func writeAudio(_ store: RecordingStore, _ reservation: RecordingStore.Reservation) throws -> URL {
        try Data("audio".utf8).write(to: reservation.fileURL)
        return reservation.fileURL
    }

    private func indexURL(_ directory: URL) -> URL {
        directory.appendingPathComponent(RecordingStore.indexFileName)
    }

    private func audioFileNames(in directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0 != RecordingStore.indexFileName })
    }

    // MARK: - Reserving a slot

    @Test func reservingHandsOutAPendingSlotInsideTheStoreDirectory() throws {
        let directory = try makeDirectory()
        let store = try RecordingStore(directory: directory)
        let id = UUID()

        let reservation = try store.reserve(id: id, createdAt: Date(timeIntervalSince1970: 1000))

        #expect(reservation.meta.id == id)
        #expect(reservation.meta.status == .pending)
        #expect(reservation.meta.fileName == "\(id.uuidString).m4a")
        #expect(reservation.fileURL == directory.appendingPathComponent("\(id.uuidString).m4a"))
        #expect(store.recordings.map(\.id) == [id])
        // The index is on disk before a single audio frame is captured.
        #expect(FileManager.default.fileExists(atPath: indexURL(directory).path))
    }

    @Test func theFileExtensionFollowsTheStoresFormat() throws {
        let directory = try makeDirectory()
        let store = try RecordingStore(directory: directory, fileExtension: "wav")
        let reservation = try store.reserve()
        #expect(reservation.fileURL.pathExtension == "wav")
    }

    @Test func creatingTheStoreCreatesItsDirectory() throws {
        let parent = try makeDirectory()
        let directory = parent.appendingPathComponent("Recordings", isDirectory: true)
        _ = try RecordingStore(directory: directory)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    // MARK: - The ring

    @Test func theDefaultRingHoldsOnlyTheLastRecording() throws {
        let directory = try makeDirectory()
        let store = try RecordingStore(directory: directory)
        #expect(store.capacity == 1)

        let first = try store.reserve()
        try writeAudio(store, first)
        // Even a *sent* recording is pushed out: one slot means the last one.
        try store.markSent(id: first.meta.id)
        let second = try store.reserve()
        try writeAudio(store, second)

        #expect(store.recordings.map(\.id) == [second.meta.id])
        #expect(!FileManager.default.fileExists(atPath: first.fileURL.path))
        #expect(try audioFileNames(in: directory) == [second.meta.fileName])
    }

    @Test func afourthRecordingEvictsTheOldestEntryAndItsAudio() throws {
        let directory = try makeDirectory()
        let store = try RecordingStore(directory: directory, capacity: 3)

        var reservations: [RecordingStore.Reservation] = []
        for index in 0..<4 {
            let reservation = try store.reserve(createdAt: Date(timeIntervalSince1970: Double(index)))
            try writeAudio(store, reservation)
            reservations.append(reservation)
        }

        #expect(store.recordings.count == 3)
        #expect(store.recordings.map(\.id) == reservations.dropFirst().map(\.meta.id))
        #expect(!FileManager.default.fileExists(atPath: reservations[0].fileURL.path))
        #expect(try audioFileNames(in: directory) == Set(reservations.dropFirst().map(\.meta.fileName)))
    }

    @Test func aSentRecordingKeepsItsSlotUntilAgeEvictsIt() throws {
        let directory = try makeDirectory()
        let store = try RecordingStore(directory: directory, capacity: 3)
        let first = try store.reserve()
        try writeAudio(store, first)

        try store.markSending(id: first.meta.id)
        try store.markSent(id: first.meta.id)

        // Two more recordings still leave it in the ring, with its audio.
        for _ in 0..<2 {
            try writeAudio(store, try store.reserve())
        }
        #expect(store.recording(id: first.meta.id)?.status == .sent)
        #expect(FileManager.default.fileExists(atPath: first.fileURL.path))

        // Only the fourth one pushes it out.
        try writeAudio(store, try store.reserve())
        #expect(store.recording(id: first.meta.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: first.fileURL.path))
    }

    @Test func theRingSizeIsConfigurable() throws {
        let directory = try makeDirectory()
        // Any size but the default, or this proves nothing.
        let store = try RecordingStore(directory: directory, capacity: 2)
        for _ in 0..<3 {
            try writeAudio(store, try store.reserve())
        }
        #expect(store.recordings.count == 2)
    }

    // MARK: - Status

    @Test func statusMovesAndIsPersisted() throws {
        let directory = try makeDirectory()
        let store = try RecordingStore(directory: directory)
        let reservation = try store.reserve()
        try writeAudio(store, reservation)
        let id = reservation.meta.id

        try store.markSending(id: id)
        #expect(store.recording(id: id)?.status == .sending)
        try store.markFailed(id: id)
        #expect(store.recording(id: id)?.status == .failed)
        #expect(store.hasFailedRecordings)
        // A failed recording can be sent again.
        try store.markSending(id: id)
        try store.markSent(id: id)
        #expect(store.recording(id: id)?.status == .sent)
        #expect(!store.hasFailedRecordings)

        let reloaded = try RecordingStore(directory: directory)
        #expect(reloaded.recording(id: id)?.status == .sent)
    }

    @Test func theCaptureWritesItsLengthBack() throws {
        let directory = try makeDirectory()
        let store = try RecordingStore(directory: directory)
        let reservation = try store.reserve()
        try writeAudio(store, reservation)

        try store.updateDuration(12.5, id: reservation.meta.id)

        #expect(store.recording(id: reservation.meta.id)?.durationSeconds == 12.5)
        let reloaded = try RecordingStore(directory: directory)
        #expect(reloaded.recording(id: reservation.meta.id)?.durationSeconds == 12.5)
    }

    @Test func touchingAnUnknownRecordingThrows() throws {
        let directory = try makeDirectory()
        let store = try RecordingStore(directory: directory)
        let stranger = UUID()

        #expect(throws: RecordingStoreError.unknownRecording(stranger)) {
            try store.markSent(id: stranger)
        }
        #expect(throws: RecordingStoreError.unknownRecording(stranger)) {
            try store.updateDuration(1, id: stranger)
        }
        #expect(store.recording(id: stranger) == nil)
        #expect(store.fileURL(id: stranger) == nil)
    }

    // MARK: - Reload, recovery and consistency

    @Test func metadataSurvivesARelaunchInRingOrder() throws {
        let directory = try makeDirectory()
        var ids: [UUID] = []
        do {
            let store = try RecordingStore(directory: directory, capacity: 3)
            for index in 0..<3 {
                let reservation = try store.reserve(createdAt: Date(timeIntervalSince1970: Double(index)))
                try writeAudio(store, reservation)
                ids.append(reservation.meta.id)
            }
            try store.updateDuration(3, id: ids[1])
        }

        let reloaded = try RecordingStore(directory: directory, capacity: 3)

        #expect(reloaded.recordings.map(\.id) == ids)
        #expect(reloaded.recordings[1].durationSeconds == 3)
        #expect(reloaded.recordings.allSatisfy { $0.status == .pending })
    }

    @Test func aRecordingStuckInSendingIsRecoveredAsFailed() throws {
        let directory = try makeDirectory()
        let id: UUID
        do {
            let store = try RecordingStore(directory: directory)
            let reservation = try store.reserve()
            try writeAudio(store, reservation)
            id = reservation.meta.id
            // The app dies here, mid-upload.
            try store.markSending(id: id)
        }

        let recovered = try RecordingStore(directory: directory)

        #expect(recovered.recording(id: id)?.status == .failed)
        #expect(recovered.hasFailedRecordings)
        // The recovery is written back, not just applied in memory.
        let again = try RecordingStore(directory: directory)
        #expect(again.recording(id: id)?.status == .failed)
    }

    @Test func anEntryWhoseAudioIsGoneIsDropped() throws {
        let directory = try makeDirectory()
        let kept: UUID
        let lost: UUID
        do {
            let store = try RecordingStore(directory: directory, capacity: 3)
            let first = try store.reserve()
            try writeAudio(store, first)
            kept = first.meta.id
            // A crash between reserving the slot and the first captured frame
            // leaves an entry with no audio behind it.
            lost = try store.reserve().meta.id
        }

        let reloaded = try RecordingStore(directory: directory, capacity: 3)

        #expect(reloaded.recordings.map(\.id) == [kept])
        #expect(reloaded.recording(id: lost) == nil)
    }

    @Test func audioNoEntryPointsAtIsSweptUp() throws {
        let directory = try makeDirectory()
        let kept: URL
        do {
            let store = try RecordingStore(directory: directory)
            kept = try writeAudio(store, try store.reserve())
        }
        let orphan = directory.appendingPathComponent("\(UUID().uuidString).m4a")
        let notOurs = directory.appendingPathComponent("notes.txt")
        try Data("audio".utf8).write(to: orphan)
        try Data("keep me".utf8).write(to: notOurs)

        _ = try RecordingStore(directory: directory)

        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(FileManager.default.fileExists(atPath: kept.path))
        // Only files named after a recording id are ours to delete.
        #expect(FileManager.default.fileExists(atPath: notOurs.path))
    }

    @Test func aLostIndexNeverTakesTheAudioWithIt() throws {
        let directory = try makeDirectory()
        let audio: URL
        do {
            let store = try RecordingStore(directory: directory)
            audio = try writeAudio(store, try store.reserve())
        }
        try Data("{ not json".utf8).write(to: indexURL(directory))

        let store = try RecordingStore(directory: directory)

        #expect(store.recordings.isEmpty)
        // The list is gone, but the recordings themselves are still there to
        // be recovered by hand.
        #expect(FileManager.default.fileExists(atPath: audio.path))
        // And the store is usable again straight away.
        #expect(try store.reserve().meta.status == .pending)
    }

    @Test func aShrunkRingIsTrimmedOnLoad() throws {
        let directory = try makeDirectory()
        var ids: [UUID] = []
        do {
            let store = try RecordingStore(directory: directory, capacity: 3)
            for _ in 0..<3 {
                let reservation = try store.reserve()
                try writeAudio(store, reservation)
                ids.append(reservation.meta.id)
            }
        }

        let smaller = try RecordingStore(directory: directory, capacity: 2)

        #expect(smaller.recordings.map(\.id) == Array(ids.suffix(2)))
        #expect(try audioFileNames(in: directory).count == 2)
    }

    @Test func theIndexOnDiskMatchesWhatTheStoreReports() throws {
        let directory = try makeDirectory()
        let store = try RecordingStore(directory: directory, capacity: 3)
        for _ in 0..<2 {
            try writeAudio(store, try store.reserve())
        }
        try store.markSent(id: store.recordings[0].id)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode([RecordingMeta].self, from: Data(contentsOf: indexURL(directory)))

        #expect(persisted == store.recordings)
        #expect(try audioFileNames(in: directory) == Set(persisted.map(\.fileName)))
    }

    @Test func aReloadedEntryEqualsTheOneInMemory() throws {
        let directory = try makeDirectory()
        let store = try RecordingStore(directory: directory)
        // The wall-clock default path, not a hand-picked round timestamp.
        let reservation = try store.reserve()
        try writeAudio(store, reservation)
        try store.updateDuration(4.25, id: reservation.meta.id)

        let reloaded = try RecordingStore(directory: directory)

        #expect(reloaded.recordings == store.recordings)
    }
}
