import ComicStructure
import Foundation
import Testing
@testable import Persistence

/// Two `CloudLibraryStore`s on separate local Libraries, sharing one fake iCloud, acting as devices A and B.
@Suite struct CloudSyncTests {
    @Test func aWorkSavedOnAAppearsOnBWithEveryPageResolving() async throws {
        let devices = try TwoDevices()
        let image = try await devices.a.store(file: tempFile("page one", ext: "png"), kind: .pageImage)
        let source = try await devices.a.store(file: tempFile("archive", ext: "cbz"), kind: .source)
        let work = comic(title: "Made on A", pageImage: image, source: source)
        try await devices.a.save(work)

        try await devices.a.sync()
        try await devices.b.sync()

        #expect(try await devices.b.works(kind: nil) == [work])
        #expect(try await devices.b.isDownloaded(image) == false)
        let page = try await devices.b.fileURL(for: image)
        #expect(try String(contentsOf: page, encoding: .utf8) == "page one")
        #expect(try await devices.b.isDownloaded(image))
    }

    @Test func aRenameOnAReachesB() async throws {
        let devices = try TwoDevices()
        var work = Work(kind: .book, title: "Old", readingDirection: .leftToRight)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.b.sync()

        work.title = "New"
        work.updatedAt = work.updatedAt.addingTimeInterval(60)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.b.sync()

        #expect(try await devices.b.works(kind: nil).map(\.title) == ["New"])
    }

    /// Both devices save the same Work; whichever syncs first, the later `updatedAt` ends up on both.
    @Test(arguments: [true, false])
    func theLaterSaveWinsOnBothDevices(earlierSyncsFirst: Bool) async throws {
        let devices = try TwoDevices()
        let original = Work(kind: .book, title: "Original", readingDirection: .leftToRight)
        try await devices.a.save(original)
        try await devices.a.sync()
        try await devices.b.sync()

        var earlier = original, later = original
        earlier.title = "Earlier on A"
        earlier.updatedAt = original.updatedAt.addingTimeInterval(10)
        later.title = "Later on B"
        later.updatedAt = original.updatedAt.addingTimeInterval(20)
        try await devices.a.save(earlier)
        try await devices.b.save(later)

        let (first, second) = earlierSyncsFirst ? (devices.a, devices.b) : (devices.b, devices.a)
        try await first.sync()
        try await second.sync()
        try await first.sync()

        #expect(try await devices.a.works(kind: nil) == [later])
        #expect(try await devices.b.works(kind: nil) == [later])
    }

    /// Two saves with the same `updatedAt` still leave both devices with the same Work.
    @Test func savesWithTheSameUpdatedAtConverge() async throws {
        let devices = try TwoDevices()
        let original = Work(kind: .book, title: "Original", readingDirection: .leftToRight)
        try await devices.a.save(original)
        try await devices.a.sync()
        try await devices.b.sync()

        var onA = original, onB = original
        onA.title = "A"
        onB.title = "B"
        onA.updatedAt = original.updatedAt.addingTimeInterval(10)
        onB.updatedAt = onA.updatedAt
        try await devices.a.save(onA)
        try await devices.b.save(onB)

        try await devices.a.sync()
        try await devices.b.sync()
        try await devices.a.sync()

        let a = try await devices.a.works(kind: nil), b = try await devices.b.works(kind: nil)
        #expect(a == b)
        #expect(a == [onA] || a == [onB])
    }

    @Test func aWorkThatBreaksAnInvariantIsNeitherSavedNorUploaded() async throws {
        let devices = try TwoDevices()
        var work = comic(title: "Bad", pageImage: FileRef("pageImage/\(UUID()).png"), source: FileRef("source/\(UUID()).cbz"))
        work.chapters[0].index = 5
        await #expect(throws: EditError.self) { try await devices.a.save(work) }

        try await devices.a.sync()
        try await devices.b.sync()

        #expect(await devices.records.all.isEmpty)
        #expect(try await devices.b.works(kind: nil).isEmpty)
    }

    /// A status that never arrives fails at the time limit instead of hanging the run.
    @Test(.timeLimit(.minutes(1))) func syncStatusIsSyncingWhileUploadingAndSyncedOnceTheQueueIsEmpty() async throws {
        let devices = try TwoDevices()
        var statuses = devices.a.syncStatus.makeAsyncIterator()
        #expect(await statuses.next() == .synced)

        let image = try await devices.a.store(file: tempFile("page", ext: "png"), kind: .pageImage)
        try await devices.a.save(comic(title: "Queued", pageImage: image, source: image))
        #expect(await statuses.next() == .syncing)

        let a = devices.a
        await devices.records.onUpload {
            #expect(await a.syncStatus.first { _ in true } == .syncing)
        }
        try await devices.a.sync()
        #expect(await statuses.next() == .synced)
    }

    @Test func aSaveMadeWhileUploadingIsUploadedByTheNextSync() async throws {
        let devices = try TwoDevices()
        var work = Work(kind: .book, title: "First", readingDirection: .leftToRight)
        try await devices.a.save(work)
        work.title = "Second"
        work.updatedAt = work.updatedAt.addingTimeInterval(60)
        let a = devices.a, second = work
        await devices.records.onUpload { try? await a.save(second) }
        try await devices.a.sync()

        try await devices.a.sync()
        try await devices.b.sync()

        #expect(try await devices.b.works(kind: nil) == [second])
    }

    @Test(.timeLimit(.minutes(1))) func writesQueuedBeforeARelaunchStillUpload() async throws {
        let devices = try TwoDevices()
        let image = try await devices.a.store(file: tempFile("page", ext: "png"), kind: .pageImage)
        let work = comic(title: "Queued", pageImage: image, source: image)
        try await devices.a.save(work)

        let relaunched = try devices.reopenA()
        #expect(await relaunched.syncStatus.first { _ in true } == .syncing)
        try await relaunched.sync()
        try await devices.b.sync()

        #expect(try await devices.b.works(kind: nil) == [work])
        _ = try await devices.b.fileURL(for: image)
    }
}
