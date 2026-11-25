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

    @Test func aDeleteOnARemovesTheWorkAndItsFilesOnBAndInICloud() async throws {
        let devices = try TwoDevices()
        let image = try await devices.a.store(file: tempFile("page", ext: "png"), kind: .pageImage)
        let source = try await devices.a.store(file: tempFile("archive", ext: "cbz"), kind: .source)
        let work = comic(title: "Doomed", pageImage: image, source: source)
        let kept = Work(kind: .book, title: "Kept", readingDirection: .leftToRight)
        try await devices.a.save(work)
        try await devices.a.save(kept)
        try await devices.a.sync()
        try await devices.b.sync()
        _ = try await devices.b.fileURL(for: image)

        try await devices.a.delete(work.id)
        try await devices.a.sync()
        try await devices.b.sync()

        #expect(try await devices.b.works(kind: nil) == [kept])
        #expect(try await devices.b.isDownloaded(image) == false)
        #expect(await devices.records.all.map(\.workID) == [kept.id])
        #expect(await devices.files.all.isEmpty)
        #expect(await devices.a.syncStatus.first { _ in true } == .synced)
    }

    /// B edits the Work while offline (before A's delete); once B is back, the tombstone wins on both.
    @Test(.timeLimit(.minutes(1))) func aSaveQueuedOnBWhileOfflineDoesNotBringADeletedWorkBack() async throws {
        let devices = try TwoDevices()
        var work = Work(kind: .book, title: "Doomed", readingDirection: .leftToRight)
        work.updatedAt = Date().addingTimeInterval(-3600)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.b.sync()

        work.title = "Edited on B while offline"
        work.updatedAt = work.updatedAt.addingTimeInterval(60)
        try await devices.b.save(work)
        try await devices.a.delete(work.id)
        try await devices.a.sync()
        try await devices.b.sync()
        try await devices.a.sync()

        #expect(try await devices.a.works(kind: nil).isEmpty)
        #expect(try await devices.b.works(kind: nil).isEmpty)
        #expect(await devices.records.all.isEmpty)
        #expect(await devices.b.syncStatus.first { _ in true } == .synced)
    }

    /// B adds a Page that hasn't uploaded yet, then A's delete arrives: the queued file goes with the Work,
    /// and B keeps syncing instead of failing on the missing file every time.
    @Test(.timeLimit(.minutes(1))) func aRemoteDeleteDropsFilesStillQueuedOnThisDevice() async throws {
        let devices = try TwoDevices()
        let image = try await devices.a.store(file: tempFile("page", ext: "png"), kind: .pageImage)
        let source = try await devices.a.store(file: tempFile("archive", ext: "cbz"), kind: .source)
        var work = comic(title: "Doomed", pageImage: image, source: source)
        work.updatedAt = Date().addingTimeInterval(-3600)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.b.sync()

        let added = try await devices.b.store(file: tempFile("page two", ext: "png"), kind: .pageImage)
        var edited = work
        edited.chapters[0].pages.append(Page(imageRef: added, pixelSize: PixelSize(width: 10, height: 10), index: 1,
                                             origin: .sourceEntry("2.png")))
        edited.updatedAt = work.updatedAt.addingTimeInterval(60)
        try await devices.b.save(edited)
        try await devices.a.delete(work.id)
        try await devices.a.sync()
        try await devices.b.sync()

        let later = Work(kind: .book, title: "Made on B later", readingDirection: .leftToRight)
        try await devices.b.save(later)
        try await devices.b.sync()

        #expect(try await devices.b.works(kind: nil) == [later])
        #expect(await devices.records.all.map(\.workID) == [later.id])
        #expect(await devices.files.all.isEmpty)
        #expect(await devices.b.syncStatus.first { _ in true } == .synced)
    }

    /// The Work is deleted here while its first file uploads: its other queued file is gone from disk by the
    /// time the sync reaches it, so the sync skips it and still finishes, leaving nothing in iCloud.
    @Test(.timeLimit(.minutes(1))) func aLocalDeleteDuringAFileUploadDoesNotFailTheSync() async throws {
        let devices = try TwoDevices()
        let image = try await devices.a.store(file: tempFile("page", ext: "png"), kind: .pageImage)
        let source = try await devices.a.store(file: tempFile("archive", ext: "cbz"), kind: .source)
        let work = comic(title: "Deleted mid-upload", pageImage: image, source: source)
        try await devices.a.save(work)
        let a = devices.a, id = work.id
        await devices.files.onCopyIn { try? await a.delete(id) }

        try await devices.a.sync()

        #expect(try await devices.a.works(kind: nil).isEmpty)
        #expect(await devices.records.all.isEmpty)
        #expect(await devices.files.all.isEmpty)
        #expect(await devices.a.syncStatus.first { _ in true } == .synced)
    }

    /// A's older save is still uploading when B's newer one lands: iCloud keeps the newer, so both end on it.
    @Test(.timeLimit(.minutes(1))) func anOlderUploadInFlightDoesNotReplaceANewerSave() async throws {
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
        let b = devices.b, newer = later
        await devices.records.onUpload {
            try? await b.save(newer)
            try? await b.sync()
        }
        try await devices.a.sync()
        try await devices.a.sync()
        try await devices.b.sync()

        #expect(try await devices.a.works(kind: nil) == [later])
        #expect(try await devices.b.works(kind: nil) == [later])
        #expect(await devices.records.all == [try WorkRecord(later)])
    }

    /// The tombstone only covers saves up to `deletedAt`; a save made after the delete is a new version.
    @Test func aSaveOnBLaterThanTheDeleteSurvivesOnBoth() async throws {
        let devices = try TwoDevices()
        var work = Work(kind: .book, title: "Deleted", readingDirection: .leftToRight)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.b.sync()

        work.title = "Saved on B after the delete"
        work.updatedAt = Date().addingTimeInterval(3600)
        try await devices.b.save(work)
        try await devices.a.delete(work.id)
        try await devices.a.sync()
        try await devices.b.sync()
        try await devices.a.sync()

        #expect(try await devices.a.works(kind: nil) == [work])
        #expect(try await devices.b.works(kind: nil) == [work])
    }

    /// B's upload of an older save lands just after A's tombstone, replacing it in iCloud; A drops that save
    /// and puts the tombstone back, so B deletes the Work too.
    /// With `clockAhead`, the Work's `updatedAt` is in the future, so the delete is stamped with it and B's
    /// edit, made with the same `updatedAt`, is exactly as late as the delete: still dropped.
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func aStaleSaveUploadedOverTheTombstoneIsDroppedEverywhere(clockAhead: Bool) async throws {
        let devices = try TwoDevices()
        var work = Work(kind: .book, title: "Doomed", readingDirection: .leftToRight)
        work.updatedAt = Date().addingTimeInterval(clockAhead ? 3600 : -3600)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.b.sync()

        work.title = "Edited on B"
        if !clockAhead { work.updatedAt = work.updatedAt.addingTimeInterval(60) }
        try await devices.b.save(work)
        let a = devices.a, id = work.id
        await devices.records.onUpload {
            try? await a.delete(id)
            try? await a.sync()
        }
        try await devices.b.sync()
        try await devices.a.sync()
        try await devices.b.sync()

        #expect(try await devices.a.works(kind: nil).isEmpty)
        #expect(try await devices.b.works(kind: nil).isEmpty)
        #expect(await devices.records.all.isEmpty)
    }

    /// A save already in flight when B learns of the delete, e.g. an autosave of the old version, is dropped.
    @Test func aLocalSaveNoLaterThanTheDeleteIsDropped() async throws {
        let devices = try TwoDevices()
        let work = Work(kind: .book, title: "Doomed", readingDirection: .leftToRight)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.b.sync()
        try await devices.a.delete(work.id)
        try await devices.a.sync()
        try await devices.b.sync()

        try await devices.b.save(work)
        try await devices.b.sync()
        try await devices.a.sync()

        #expect(try await devices.a.works(kind: nil).isEmpty)
        #expect(try await devices.b.works(kind: nil).isEmpty)
    }

    @Test func aDeleteStillDropsOlderSavesAfterARelaunch() async throws {
        let devices = try TwoDevices()
        let work = Work(kind: .book, title: "Doomed", readingDirection: .leftToRight)
        try await devices.a.save(work)
        try await devices.a.delete(work.id)
        try await devices.a.sync()

        let relaunched = try devices.reopenA()
        try await relaunched.save(work)

        #expect(try await relaunched.works(kind: nil).isEmpty)
    }

    @Test func evictingAnUploadedFileFreesItAndFileURLDownloadsItAgain() async throws {
        let devices = try TwoDevices()
        let ref = try await devices.a.store(file: tempFile("render", ext: "mp4"), kind: .renderVideo)
        try await devices.a.sync()

        try await devices.a.evictLocalCopy(ref)

        #expect(try await devices.a.isDownloaded(ref) == false)
        let url = try await devices.a.fileURL(for: ref)
        #expect(try String(contentsOf: url, encoding: .utf8) == "render")
        #expect(try await devices.a.isDownloaded(ref))
    }

    @Test func aFileStillUploadingToICloudCannotBeEvicted() async throws {
        let devices = try TwoDevices()
        await devices.files.holdUploads()
        let ref = try await devices.a.store(file: tempFile("render", ext: "mp4"), kind: .renderVideo)
        try await devices.a.sync()

        await #expect(throws: PersistenceError.notSafelyInCloud(ref)) { try await devices.a.evictLocalCopy(ref) }
        #expect(try await devices.a.isDownloaded(ref))
    }

    /// A Work saved on a device whose clock runs ahead is still covered by its delete, on both devices.
    @Test func deletingAWorkStampedInTheFutureStillDeletesItEverywhere() async throws {
        let devices = try TwoDevices()
        var work = Work(kind: .book, title: "From the future", readingDirection: .leftToRight)
        work.updatedAt = Date().addingTimeInterval(3600)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.b.sync()

        try await devices.a.delete(work.id)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.b.sync()

        #expect(try await devices.a.works(kind: nil).isEmpty)
        #expect(try await devices.b.works(kind: nil).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func aWorkDeletedBeforeItEverSyncedLeavesNothingInICloud() async throws {
        let devices = try TwoDevices()
        let synced = Work(kind: .book, title: "Synced", readingDirection: .leftToRight)
        try await devices.a.save(synced)
        try await devices.a.sync()
        try await devices.a.delete(synced.id)
        #expect(await devices.a.syncStatus.first { _ in true } == .syncing)

        let image = try await devices.a.store(file: tempFile("page", ext: "png"), kind: .pageImage)
        let work = comic(title: "Never synced", pageImage: image, source: image)
        try await devices.a.save(work)
        try await devices.a.delete(work.id)
        try await devices.a.sync()

        #expect(await devices.a.syncStatus.first { _ in true } == .synced)
        #expect(await devices.records.all.isEmpty)
        #expect(await devices.files.all.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func withTheAccountUnavailableEverythingWorksLocallyAndUploadsOnceItIsBack() async throws {
        let devices = try TwoDevices()
        devices.accountA.set(.unavailable)
        let image = try await devices.a.store(file: tempFile("page", ext: "png"), kind: .pageImage)
        var work = comic(title: "Made offline", pageImage: image, source: image)
        try await devices.a.save(work)
        work.title = "Renamed offline"
        work.updatedAt = work.updatedAt.addingTimeInterval(60)
        try await devices.a.save(work)
        let doomed = Work(kind: .book, title: "Deleted offline", readingDirection: .leftToRight)
        try await devices.a.save(doomed)
        try await devices.a.delete(doomed.id)

        await #expect(throws: ICloudError.accountUnavailable) { try await devices.a.sync() }
        #expect(try await devices.a.works(kind: nil) == [work])
        #expect(try await devices.a.isDownloaded(image))
        #expect(await devices.a.syncStatus.first { _ in true } == .offline)
        #expect(await devices.records.all.isEmpty)

        devices.accountA.set(.available)
        try await devices.a.sync()
        try await devices.b.sync()

        #expect(try await devices.b.works(kind: nil) == [work])
        let page = try await devices.b.fileURL(for: image)
        #expect(try String(contentsOf: page, encoding: .utf8) == "page")
        #expect(await devices.a.syncStatus.first { _ in true } == .synced)
    }

    @Test(.timeLimit(.minutes(1))) func withICloudFullEverythingStaysLocalAndUploadsOnceThereIsSpace() async throws {
        let devices = try TwoDevices()
        devices.accountA.set(.full)
        let image = try await devices.a.store(file: tempFile("page", ext: "png"), kind: .pageImage)
        let work = comic(title: "Made while full", pageImage: image, source: image)
        try await devices.a.save(work)

        await #expect(throws: ICloudError.quotaExceeded) { try await devices.a.sync() }
        #expect(try await devices.a.works(kind: nil) == [work])
        #expect(await devices.a.syncStatus.first { _ in true } == .iCloudFull)
        #expect(await devices.records.all.isEmpty)
        #expect(await devices.files.all.isEmpty)

        devices.accountA.set(.available)
        try await devices.a.sync()
        try await devices.b.sync()

        #expect(try await devices.b.works(kind: nil) == [work])
        let page = try await devices.b.fileURL(for: image)
        #expect(try String(contentsOf: page, encoding: .utf8) == "page")
        #expect(await devices.a.syncStatus.first { _ in true } == .synced)
    }

    enum Tampering: CaseIterable, Sendable { case badJSON, invariantViolation, pathTraversalFileRef }

    /// A tampered record for a Work B already has arrives first in a batch, ahead of a good record.
    @Test(.timeLimit(.minutes(1)), arguments: Tampering.allCases)
    func aTamperedRemoteRecordIsReportedAndSkippedAndTheRestOfTheBatchSyncs(_ tampering: Tampering) async throws {
        let devices = try TwoDevices()
        let image = try await devices.a.store(file: tempFile("page", ext: "png"), kind: .pageImage)
        let work = comic(title: "Intact", pageImage: image, source: image)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.b.sync()

        var tampered = work
        tampered.title = "Tampered"
        tampered.updatedAt = work.updatedAt.addingTimeInterval(60)
        let payload: Data
        switch tampering {
        case .badJSON: payload = Data("{".utf8)
        case .invariantViolation:
            tampered.chapters[0].index = 5
            payload = try ComicSchema.encode(tampered)
        case .pathTraversalFileRef:
            tampered.chapters[0].pages[0].imageRef = FileRef("pageImage/../../../etc/passwd")
            payload = try ComicSchema.encode(tampered)
        }
        let good = Work(kind: .book, title: "Good", readingDirection: .leftToRight)
        try await devices.records.save([
            WorkRecord(workID: work.id, schemaVersion: ComicSchema.currentVersion, updatedAt: tampered.updatedAt, payload: payload),
            WorkRecord(good),
        ])

        try await devices.b.sync()

        #expect(try await devices.b.works(kind: nil) == [work, good])
        let status = await devices.b.syncStatus.first { _ in true }
        guard case .error = status else { Issue.record("status is \(String(describing: status)), not .error"); return }
    }

    @Test(.timeLimit(.minutes(1))) func retriesBackOffExponentiallyUpToFifteenMinutes() async throws {
        let devices = try TwoDevices()
        devices.accountA.set(.unavailable)
        let syncing = Task { await devices.a.keepSynced() }
        defer { syncing.cancel() }

        var sleeps = devices.clock.sleeps.makeAsyncIterator()
        var waits: [Duration] = []
        for _ in 0..<9 {
            let wait = try #require(await sleeps.next())
            waits.append(wait)
            devices.clock.advance(by: wait)
        }

        #expect(waits == [10, 20, 40, 80, 160, 320, 640, 900, 900].map { .seconds($0) })
    }

    /// The app calls `requestSync` on an account-change notification.
    @Test(.timeLimit(.minutes(1))) func whenTheAccountComesBackTheQueueUploadsWithoutWaitingOutTheBackoff() async throws {
        let devices = try TwoDevices()
        devices.accountA.set(.unavailable)
        let work = Work(kind: .book, title: "Queued offline", readingDirection: .leftToRight)
        try await devices.a.save(work)
        let syncing = Task { await devices.a.keepSynced() }
        defer { syncing.cancel() }
        var sleeps = devices.clock.sleeps.makeAsyncIterator()
        _ = await sleeps.next()

        devices.accountA.set(.available)
        await devices.a.requestSync()
        for await status in devices.a.syncStatus where status == .synced { break }
        try await devices.b.sync()

        #expect(try await devices.b.works(kind: nil) == [work])
    }

    /// After a sync succeeds nothing waits on the clock, and the next failure backs off from the start.
    @Test(.timeLimit(.minutes(1))) func aSuccessfulSyncStartsTheBackoffOver() async throws {
        let devices = try TwoDevices()
        devices.accountA.set(.unavailable)
        let syncing = Task { await devices.a.keepSynced() }
        defer { syncing.cancel() }
        var sleeps = devices.clock.sleeps.makeAsyncIterator()
        for _ in 0..<3 { devices.clock.advance(by: try #require(await sleeps.next())) }
        devices.accountA.set(.available)
        await devices.a.requestSync()
        for await status in devices.a.syncStatus where status == .synced { break }

        devices.accountA.set(.unavailable)
        await devices.a.requestSync()
        let first = try #require(await sleeps.next())
        devices.clock.advance(by: first)
        let second = try #require(await sleeps.next())

        #expect([first, second] == [.seconds(10), .seconds(20)])
    }

    /// A second sync started while one is uploading waits for it, so nothing is uploaded twice.
    @Test(.timeLimit(.minutes(1))) func aSyncStartedDuringAnotherWaitsForIt() async throws {
        let devices = try TwoDevices()
        try await devices.a.save(Work(kind: .book, title: "Once", readingDirection: .leftToRight))
        let a = devices.a, second = Box<Task<Void, Error>>()
        await devices.records.onUpload {
            await second.set(Task { try await a.sync() })
            for _ in 0..<1000 { await Task.yield() }
        }

        try await devices.a.sync()
        try await #require(await second.value).value

        #expect(await devices.records.uploads == 1)
    }

    /// The tombstone uploads but removing the Work's files fails; those removals are still queued after a relaunch.
    @Test(.timeLimit(.minutes(1))) func fileRemovalsLeftByAFailedSyncStayQueuedAcrossARelaunch() async throws {
        let devices = try TwoDevices()
        let image = try await devices.a.store(file: tempFile("page", ext: "png"), kind: .pageImage)
        let work = comic(title: "Doomed", pageImage: image, source: image)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.a.delete(work.id)
        await devices.files.refuseRemovals(true)
        await #expect(throws: ICloudError.accountUnavailable) { try await devices.a.sync() }
        #expect(await devices.records.all.isEmpty)

        let relaunched = try devices.reopenA()
        #expect(await relaunched.syncStatus.first { _ in true } == .syncing)
        await devices.files.refuseRemovals(false)
        try await relaunched.sync()

        #expect(await devices.files.all.isEmpty)
        #expect(await relaunched.syncStatus.first { _ in true } == .synced)
    }

    /// A request that comes while a sync is running isn't lost: another sync follows and uploads the new save.
    @Test(.timeLimit(.minutes(1))) func aSyncRequestedWhileSyncingRunsAnotherSync() async throws {
        let devices = try TwoDevices()
        try await devices.a.save(Work(kind: .book, title: "First", readingDirection: .leftToRight))
        let later = Work(kind: .book, title: "Saved during the upload", readingDirection: .leftToRight)
        let a = devices.a
        await devices.records.onUpload {
            try? await a.save(later)
            await a.requestSync()
        }
        let syncing = Task { await devices.a.keepSynced() }
        defer { syncing.cancel() }

        while await !devices.records.all.contains(where: { $0.workID == later.id }) { await Task.yield() }
    }

    /// The record's header names one Work but its payload is another: only the payload is trusted.
    @Test func aRemoteRecordIsAppliedAsItsPayloadSaysNotItsHeader() async throws {
        let devices = try TwoDevices()
        let work = Work(kind: .book, title: "Intact", readingDirection: .leftToRight)
        try await devices.a.save(work)
        try await devices.a.sync()
        try await devices.b.sync()

        var other = Work(kind: .book, title: "Other", readingDirection: .leftToRight)
        other.updatedAt = work.updatedAt.addingTimeInterval(60)
        try await devices.records.save([WorkRecord(workID: work.id, schemaVersion: ComicSchema.currentVersion,
                                                   updatedAt: other.updatedAt, payload: ComicSchema.encode(other))])
        try await devices.b.sync()

        #expect(Set(try await devices.b.works(kind: nil).map(\.id)) == [work.id, other.id])
    }

    /// The change token is kept with the Library, so a relaunch reads only what changed since the last sync.
    @Test func aRelaunchedDeviceFetchesFromWhereItsLastSyncReadUpTo() async throws {
        let devices = try TwoDevices()
        try await devices.a.save(Work(kind: .book, title: "Synced", readingDirection: .leftToRight))
        try await devices.a.sync()

        try await devices.reopenA().sync()

        let tokens = await devices.records.fetchedSince
        let issued = await devices.records.issued
        try #require(tokens.count == 2 && issued.count == 2)
        #expect(tokens[1] == issued[0])
    }

    /// Something iCloud refused for another reason (e.g. the CloudKit schema isn't deployed): the status says
    /// what, so it isn't stuck on `.syncing`, and nothing queued is lost.
    @Test(.timeLimit(.minutes(1))) func anUnexpectedFailureIsReportedAsAnErrorWithItsMessage() async throws {
        struct Refused: Error, CustomStringConvertible { var description: String { "schema not deployed" } }
        struct RefusingRecords: RecordSyncBackend {
            func fetchChanges(since token: ChangeToken?) async throws -> RecordChanges { throw Refused() }
            func save(_ records: [WorkRecord]) async throws {}
            func delete(_ tombstones: [Tombstone]) async throws {}
        }
        let store = try CloudLibraryStore(root: FileManager.default.temporaryDirectory.appending(path: "Refused-\(UUID())"),
                                          records: RefusingRecords(), files: FakeUbiquitousFileContainer())
        try await store.save(Work(kind: .book, title: "Kept", readingDirection: .leftToRight))

        await #expect(throws: Refused.self) { try await store.sync() }

        #expect(await store.syncStatus.first { _ in true } == .error("schema not deployed"))
        #expect(try await store.works(kind: nil).map(\.title) == ["Kept"])
    }
}
