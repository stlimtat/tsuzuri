import ComicStructure
import Foundation
import Persistence
import Testing

/// The golden Page the app bundles for its sample Work (800×1200).
let goldenPage = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Fixtures/golden/pages/p01-vertical-grid.png")

func emptyLibraryRoot() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "DebugLibraryModelTests-\(UUID())")
}

@MainActor @Suite struct DebugLibraryModelTests {
    @Test func sampleWorkIsListedWithItsPageCountAndDownloadedCount() async throws {
        let model = DebugLibraryModel(store: try LocalLibraryStore(root: emptyLibraryRoot()))

        try await model.createSampleWork(fromPage: goldenPage, name: "Sample")

        #expect(model.rows.map(\.name) == ["Sample"])
        #expect(model.rows.first?.pageCount == 1)
        #expect(model.rows.first?.downloadedPageCount == 1)
    }

    @Test func sampleWorkIsARightToLeftComicWhosePageKeepsTheImageSize() async throws {
        let store = try LocalLibraryStore(root: emptyLibraryRoot())
        try await DebugLibraryModel(store: store).createSampleWork(fromPage: goldenPage, name: "Sample")

        let work = try #require(try await store.works(kind: nil).first)
        #expect(work.kind == .comic)
        #expect(work.readingDirection == .rightToLeft)
        let page = try #require(work.chapters.first?.pages.first)
        #expect(page.pixelSize == PixelSize(width: 800, height: 1200))
        #expect(page.origin == .sourceEntry("p01-vertical-grid.png"))
    }

    @Test func sampleWorkSurvivesRelaunch() async throws {
        let root = emptyLibraryRoot()
        try await DebugLibraryModel(store: try LocalLibraryStore(root: root)).createSampleWork(fromPage: goldenPage, name: "Sample")

        let relaunched = DebugLibraryModel(store: try LocalLibraryStore(root: root))
        try await relaunched.reload()

        #expect(relaunched.rows.map(\.name) == ["Sample"])
        #expect(relaunched.rows.first?.downloadedPageCount == 1)
    }

    @Test func renamingUpdatesTheListAndTheStoredWorkAndSurvivesRelaunch() async throws {
        let root = emptyLibraryRoot()
        let store = try LocalLibraryStore(root: root)
        let model = DebugLibraryModel(store: store)
        try await model.createSampleWork(fromPage: goldenPage, name: "Old")
        let id = try #require(model.rows.first?.id)
        let renamedAt = Date(timeIntervalSince1970: 2_000_000_000)

        try await model.rename(id, to: "New", at: renamedAt)

        #expect(model.rows.map(\.name) == ["New"])
        let stored = try #require(try await LocalLibraryStore(root: root).works(kind: nil).first)
        #expect(stored.title == "New")
        #expect(stored.updatedAt == renamedAt)
    }

    @Test func renamingTrimsSpacesAroundTheName() async throws {
        let root = emptyLibraryRoot()
        let model = DebugLibraryModel(store: try LocalLibraryStore(root: root))
        try await model.createSampleWork(fromPage: goldenPage, name: "Old")
        let id = try #require(model.rows.first?.id)

        try await model.rename(id, to: "  綴り \"Vol.1\" 📚 \n", at: Date(timeIntervalSince1970: 2_000_000_000))

        #expect(try await LocalLibraryStore(root: root).works(kind: nil).first?.title == "綴り \"Vol.1\" 📚")
    }

    @Test func renamingToABlankNameLeavesTheWorkUnchanged() async throws {
        let root = emptyLibraryRoot()
        let model = DebugLibraryModel(store: try LocalLibraryStore(root: root))
        try await model.createSampleWork(fromPage: goldenPage, name: "Old")
        let before = try #require(try await LocalLibraryStore(root: root).works(kind: nil).first)

        try await model.rename(before.id, to: "  \n", at: Date(timeIntervalSince1970: 2_000_000_000))

        #expect(model.rows.map(\.name) == ["Old"])
        #expect(try await LocalLibraryStore(root: root).works(kind: nil) == [before])
    }

    @Test func renamingAWorkThatIsGoneFails() async throws {
        let model = DebugLibraryModel(store: try LocalLibraryStore(root: emptyLibraryRoot()))
        let missing = UUID()

        await #expect(throws: PersistenceError.notFound(missing.uuidString)) {
            try await model.rename(missing, to: "New")
        }
    }

    @Test func deletingRemovesTheWorkAndItsPageFiles() async throws {
        let root = emptyLibraryRoot()
        let store = try LocalLibraryStore(root: root)
        let model = DebugLibraryModel(store: store)
        try await model.createSampleWork(fromPage: goldenPage, name: "Doomed")
        try await model.createSampleWork(fromPage: goldenPage, name: "Kept")
        let doomed = try #require(try await store.works(kind: nil).first { $0.title == "Doomed" })
        let pageFile = doomed.chapters[0].pages[0].imageRef

        try await model.delete(doomed.id)

        #expect(model.rows.map(\.name) == ["Kept"])
        let relaunched = try LocalLibraryStore(root: root)
        #expect(try await relaunched.works(kind: nil).map(\.title) == ["Kept"])
        #expect(try await relaunched.isDownloaded(pageFile) == false)
    }

    @Test func downloadedCountLeavesOutPagesOnlyInICloud() async throws {
        let store = PartlyDownloadedStore(local: try LocalLibraryStore(root: emptyLibraryRoot()))
        let model = DebugLibraryModel(store: store)
        try await model.createSampleWork(fromPage: goldenPage, name: "Sample")
        let page = try #require(try await store.works(kind: nil).first?.chapters.first?.pages.first)

        await store.markOnlyInICloud(page.imageRef)
        try await model.reload()

        #expect(model.rows.first?.pageCount == 1)
        #expect(model.rows.first?.downloadedPageCount == 0)
    }

    /// Opening a Work whose Page is only in iCloud downloads it, and the list then counts it as downloaded.
    @Test func openingAWorksFirstPageDownloadsItAndCountsItAsDownloaded() async throws {
        let store = PartlyDownloadedStore(local: try LocalLibraryStore(root: emptyLibraryRoot()))
        let model = DebugLibraryModel(store: store)
        try await model.createSampleWork(fromPage: goldenPage, name: "Sample")
        let work = try #require(try await store.works(kind: nil).first)
        await store.markOnlyInICloud(work.chapters[0].pages[0].imageRef)
        try await model.reload()

        let page = try await model.firstPageFile(of: work.id)

        #expect(try Data(contentsOf: page) == Data(contentsOf: goldenPage))
        #expect(model.rows.first?.downloadedPageCount == 1)
    }

    @Test func aSamplePageThatIsNotAnImageAddsNoWork() async throws {
        let root = emptyLibraryRoot()
        let model = DebugLibraryModel(store: try LocalLibraryStore(root: root))
        let notAnImage = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).png")
        try Data("not a png".utf8).write(to: notAnImage)

        await #expect(throws: DebugLibraryError.unreadablePage(notAnImage)) {
            try await model.createSampleWork(fromPage: notAnImage, name: "Broken")
        }
        #expect(try await LocalLibraryStore(root: root).works(kind: nil).isEmpty)
    }
}

/// A Library whose chosen files are only in iCloud: a `LocalLibraryStore` that reports them as not downloaded.
actor PartlyDownloadedStore: LibraryStore {
    let local: LocalLibraryStore
    private var onlyInICloud: Set<FileRef> = []
    init(local: LocalLibraryStore) { self.local = local }

    func markOnlyInICloud(_ ref: FileRef) { onlyInICloud.insert(ref) }

    func works(kind: WorkKind?) async throws -> [Work] { try await local.works(kind: kind) }
    func save(_ work: Work) async throws { try await local.save(work) }
    func delete(_ workID: Work.ID) async throws { try await local.delete(workID) }
    /// Downloads the file: from now on it counts as on this device.
    func fileURL(for ref: FileRef) async throws -> URL {
        onlyInICloud.remove(ref)
        return try await local.fileURL(for: ref)
    }
    func isDownloaded(_ ref: FileRef) async throws -> Bool {
        if onlyInICloud.contains(ref) { return false }
        return try await local.isDownloaded(ref)
    }
    func store(file: URL, kind: FileKind) async throws -> FileRef { try await local.store(file: file, kind: kind) }
    func evictLocalCopy(_ ref: FileRef) async throws { try await local.evictLocalCopy(ref) }
    nonisolated var syncStatus: AsyncStream<SyncStatus> { local.syncStatus }
}

@MainActor @Suite struct DebugLibrarySyncTests {
    @Test(.timeLimit(.minutes(1))) func theModelFollowsTheStoresSyncStatusAndShowsTheBanner() async throws {
        let store = StatusStore(local: try LocalLibraryStore(root: emptyLibraryRoot()))
        let model = DebugLibraryModel(store: store)
        let following = Task { await model.followSyncStatus() }
        defer { following.cancel() }

        store.publish(.offline)
        while model.syncStatus != .offline { await Task.yield() }
        #expect(model.banner == .offline)

        store.publish(.synced)
        while model.syncStatus != .synced { await Task.yield() }
        #expect(model.banner == nil)
    }

    /// Refreshing syncs first, so a Work another device made is listed.
    @Test func refreshingSyncsThenListsWhatTheSyncBroughtIn() async throws {
        let store = try LocalLibraryStore(root: emptyLibraryRoot())
        let model = DebugLibraryModel(store: store, sync: {
            try await store.save(Work(kind: .comic, title: "Made on iPad", readingDirection: .rightToLeft))
        })

        try await model.refresh()

        #expect(model.rows.map(\.name) == ["Made on iPad"])
    }

    /// Offline is shown by the status and banner, not as a failure: refreshing still lists the local Library.
    @Test func refreshingWhileICloudIsUnavailableStillListsTheLibrary() async throws {
        let store = try LocalLibraryStore(root: emptyLibraryRoot())
        try await store.save(Work(kind: .comic, title: "Local", readingDirection: .rightToLeft))
        let model = DebugLibraryModel(store: store, sync: { throw ICloudError.accountUnavailable })

        try await model.refresh()

        #expect(model.rows.map(\.name) == ["Local"])
    }
}

/// A Library whose sync status the test sets: a `LocalLibraryStore` with a status stream the test feeds.
final class StatusStore: LibraryStore {
    let local: LocalLibraryStore
    private let statuses: AsyncStream<SyncStatus>
    private let feed: AsyncStream<SyncStatus>.Continuation
    init(local: LocalLibraryStore) {
        self.local = local
        (statuses, feed) = AsyncStream.makeStream()
    }

    func publish(_ status: SyncStatus) { feed.yield(status) }

    func works(kind: WorkKind?) async throws -> [Work] { try await local.works(kind: kind) }
    func save(_ work: Work) async throws { try await local.save(work) }
    func delete(_ workID: Work.ID) async throws { try await local.delete(workID) }
    func fileURL(for ref: FileRef) async throws -> URL { try await local.fileURL(for: ref) }
    func isDownloaded(_ ref: FileRef) async throws -> Bool { try await local.isDownloaded(ref) }
    func store(file: URL, kind: FileKind) async throws -> FileRef { try await local.store(file: file, kind: kind) }
    func evictLocalCopy(_ ref: FileRef) async throws { try await local.evictLocalCopy(ref) }
    var syncStatus: AsyncStream<SyncStatus> { statuses }
}
