import ComicStructure
import Foundation
import Testing
@testable import Persistence

/// A fresh store on an empty Library, plus the store-specific hooks the contract needs.
struct StoreFixture {
    let store: any LibraryStore
    /// Another store on the same Library, as after a relaunch.
    let reopen: () throws -> any LibraryStore
    /// Puts an undecodable record into the store's local Library.
    let corruptLocalRecord: () throws -> Void
}

/// Builds a `StoreFixture`; every store implementing `LibraryStore` adds one to `all`.
struct StoreFactory: Sendable, CustomTestStringConvertible {
    let name: String
    let make: @Sendable () throws -> StoreFixture
    var testDescription: String { name }

    static let local = StoreFactory(name: "LocalLibraryStore") {
        let root = FileManager.default.temporaryDirectory.appending(path: "LibraryStoreTests-\(UUID())")
        return StoreFixture(
            store: try LocalLibraryStore(root: root),
            reopen: { try LocalLibraryStore(root: root) },
            corruptLocalRecord: { try Data("{".utf8).write(to: root.appending(path: "works/\(UUID()).json")) })
    }

    static let cloud = StoreFactory(name: "CloudLibraryStore") {
        let root = FileManager.default.temporaryDirectory.appending(path: "LibraryStoreTests-\(UUID())")
        let records = FakeRecordSyncBackend(), files = FakeUbiquitousFileContainer()
        return StoreFixture(
            store: try CloudLibraryStore(root: root, records: records, files: files),
            reopen: { try CloudLibraryStore(root: root, records: records, files: files) },
            corruptLocalRecord: { try Data("{".utf8).write(to: root.appending(path: "works/\(UUID()).json")) })
    }

    static let all: [StoreFactory] = [.local, .cloud]
}

func tempFile(_ contents: String, ext: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).\(ext)")
    try Data(contents.utf8).write(to: url)
    return url
}

func comic(title: String, pageImage: FileRef, source: FileRef) -> Work {
    let page = Page(imageRef: pageImage, pixelSize: PixelSize(width: 10, height: 10), index: 0, origin: .sourceEntry("1.png"))
    return Work(kind: .comic, title: title, readingDirection: .rightToLeft,
                sources: [Source(fileName: "a.cbz", contentType: "public.zip-archive", byteSize: 3, fileRef: source)],
                chapters: [Chapter(title: "1", index: 0, pages: [page])])
}

func book(title: String, epub: FileRef, cover: FileRef? = nil) -> Work {
    Work(kind: .book, title: title, readingDirection: .leftToRight,
         sources: [Source(fileName: "book.epub", contentType: "org.idpf.epub-container", byteSize: 3, fileRef: epub)],
         book: BookSummary(authors: ["Natsume Sōseki"], cover: cover))
}

/// The book as a save that wrote it a new EPUB (and cover) leaves it: naming the new files, with a later `updatedAt`.
func resaved(_ work: Work, epub: FileRef, cover: FileRef? = nil) -> Work {
    var saved = book(title: work.title, epub: epub, cover: cover)
    saved.id = work.id
    saved.createdAt = work.createdAt
    saved.updatedAt = work.updatedAt.addingTimeInterval(60)
    return saved
}

/// The behaviour every `LibraryStore` shares, run against each store in `StoreFactory.all`.
@Suite struct LibraryStoreContractTests {
    static let escapingFileRefs = ["../../etc/passwd", "pageImage/../../x.png", "/etc/passwd", "nope/\(UUID()).png",
                                   "pageImage/notauuid.png", "pageImage/\(UUID()).p/g", "pageImage/\(UUID()).p.g",
                                   "pageImage/\(UUID()).", "pageImage/\(UUID()).abcdefghijk"]

    @Test(arguments: StoreFactory.all)
    func savedWorksAreReadBackFilteredByKind(_ factory: StoreFactory) async throws {
        let fixture = try factory.make()
        let store = fixture.store
        let comicWork = comic(title: "Comic", pageImage: FileRef("pageImage/x.png"), source: FileRef("source/y.cbz"))
        let book = Work(kind: .book, title: "Book", readingDirection: .leftToRight)
        try await store.save(comicWork)
        try await store.save(book)

        #expect(Set(try await store.works(kind: nil)) == [comicWork, book])
        #expect(try await store.works(kind: .book) == [book])
        // A second store on the same Library sees the same Works (survives relaunch).
        #expect(try await fixture.reopen().works(kind: .comic) == [comicWork])
    }

    @Test(arguments: StoreFactory.all)
    func savingAgainReplacesTheWork(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        var work = Work(kind: .book, title: "Old", readingDirection: .leftToRight)
        try await store.save(work)
        work.title = "New"
        try await store.save(work)
        #expect(try await store.works(kind: nil).map(\.title) == ["New"])
    }

    @Test(arguments: StoreFactory.all)
    func storedFilesResolveToTheirContents(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        let ref = try await store.store(file: tempFile("image", ext: "png"), kind: .pageImage)
        #expect(ref.id.hasPrefix("pageImage/") && ref.id.hasSuffix(".png"))
        let url = try await store.fileURL(for: ref)
        #expect(try String(contentsOf: url, encoding: .utf8) == "image")
    }

    @Test(arguments: StoreFactory.all)
    func aStoredFileIsDownloaded(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        let ref = try await store.store(file: tempFile("image", ext: "png"), kind: .pageImage)
        #expect(try await store.isDownloaded(ref))
    }

    @Test(arguments: StoreFactory.all)
    func aFileNeverStoredIsNotDownloaded(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        #expect(try await store.isDownloaded(FileRef("pageImage/\(UUID()).png")) == false)
    }

    @Test(arguments: StoreFactory.all)
    func deletingAWorkRemovesItsRecordAndFiles(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        let image = try await store.store(file: tempFile("i", ext: "png"), kind: .pageImage)
        let source = try await store.store(file: tempFile("s", ext: "cbz"), kind: .source)
        let crop = try await store.store(file: tempFile("c", ext: "png"), kind: .referenceCrop)
        let video = try await store.store(file: tempFile("v", ext: "mp4"), kind: .renderVideo)
        let other = try await store.store(file: tempFile("o", ext: "png"), kind: .pageImage)
        var work = comic(title: "Gone", pageImage: image, source: source)
        work.cast.characters = [Character(name: "Aoi", referenceCrops: [crop])]
        work.renders = [Render(chapterID: work.chapters[0].id, panelIDs: [UUID()], videoRef: video, inputsHash: "h", providerID: "p")]
        let kept = comic(title: "Kept", pageImage: other, source: other)
        try await store.save(work)
        try await store.save(kept)

        try await store.delete(work.id)

        #expect(try await store.works(kind: nil) == [kept])
        for gone in [image, source, crop, video] {
            #expect(try await store.isDownloaded(gone) == false)
        }
        _ = try await store.fileURL(for: other)
    }

    @Test(arguments: StoreFactory.all)
    func aStoredCoverResolvesToItsContentsAfterARelaunch(_ factory: StoreFactory) async throws {
        let fixture = try factory.make()
        let cover = try await fixture.store.store(file: tempFile("cover", ext: "jpg"), kind: .cover)
        #expect(cover.id.hasPrefix("cover/") && cover.id.hasSuffix(".jpg"))
        let url = try await fixture.reopen().fileURL(for: cover)
        #expect(try String(contentsOf: url, encoding: .utf8) == "cover")
    }

    @Test(arguments: StoreFactory.all)
    func deletingABookRemovesItsEPUBAndCover(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        let epub = try await store.store(file: tempFile("epub", ext: "epub"), kind: .source)
        let cover = try await store.store(file: tempFile("cover", ext: "jpg"), kind: .cover)
        let work = book(title: "Gone", epub: epub, cover: cover)
        try await store.save(work)

        try await store.delete(work.id)

        #expect(try await store.isDownloaded(epub) == false)
        #expect(try await store.isDownloaded(cover) == false)
    }

    /// A book save stores the new EPUB and cover, saves the Work naming them, then removes the replaced files.
    @Test(arguments: StoreFactory.all)
    func aBookSaveThatReplacesItsFilesLeavesOnlyTheNewOnes(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        let oldEPUB = try await store.store(file: tempFile("old epub", ext: "epub"), kind: .source)
        let oldCover = try await store.store(file: tempFile("old cover", ext: "jpg"), kind: .cover)
        let original = book(title: "Kokoro", epub: oldEPUB, cover: oldCover)
        try await store.save(original)

        let newEPUB = try await store.store(file: tempFile("new epub", ext: "epub"), kind: .source)
        let newCover = try await store.store(file: tempFile("new cover", ext: "jpg"), kind: .cover)
        let saved = resaved(original, epub: newEPUB, cover: newCover)
        try await store.save(saved)
        try await store.removeFile(oldEPUB)
        try await store.removeFile(oldCover)

        #expect(try await store.works(kind: nil) == [saved])
        for gone in [oldEPUB, oldCover] {
            await #expect(throws: PersistenceError.notFound(gone.id)) { try await store.fileURL(for: gone) }
        }
        #expect(try String(contentsOf: try await store.fileURL(for: newEPUB), encoding: .utf8) == "new epub")
        #expect(try String(contentsOf: try await store.fileURL(for: newCover), encoding: .utf8) == "new cover")
    }

    @Test(arguments: StoreFactory.all)
    func removingAFileThatIsAlreadyGoneIsNoError(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        let ref = try await store.store(file: tempFile("epub", ext: "epub"), kind: .source)

        try await store.removeFile(ref)
        try await store.removeFile(ref)
        try await store.removeFile(FileRef("source/\(UUID()).epub"))

        #expect(try await store.isDownloaded(ref) == false)
    }

    @Test(arguments: StoreFactory.all)
    func removeFileRejectsFileRefsThatEscapeTheLibrary(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        for id in Self.escapingFileRefs {
            await #expect(throws: PersistenceError.invalidFileRef(id)) { try await store.removeFile(FileRef(id)) }
        }
    }

    @Test(arguments: StoreFactory.all)
    func fileRefsCannotEscapeTheLibrary(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        for id in Self.escapingFileRefs {
            await #expect(throws: PersistenceError.invalidFileRef(id)) { try await store.fileURL(for: FileRef(id)) }
        }
    }

    @Test(arguments: StoreFactory.all)
    func isDownloadedRejectsFileRefsThatEscapeTheLibrary(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        for id in Self.escapingFileRefs {
            await #expect(throws: PersistenceError.invalidFileRef(id)) { try await store.isDownloaded(FileRef(id)) }
        }
    }

    @Test(arguments: StoreFactory.all)
    func evictionRejectsFileRefsThatEscapeTheLibrary(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        for id in Self.escapingFileRefs {
            await #expect(throws: PersistenceError.invalidFileRef(id)) { try await store.evictLocalCopy(FileRef(id)) }
        }
    }

    @Test(arguments: StoreFactory.all)
    func evictionNeverDropsTheOnlyCopy(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        let ref = try await store.store(file: tempFile("r", ext: "mp4"), kind: .renderVideo)
        await #expect(throws: PersistenceError.notSafelyInCloud(ref)) { try await store.evictLocalCopy(ref) }
        _ = try await store.fileURL(for: ref)
    }

    @Test(arguments: StoreFactory.all)
    func aWorkThatBreaksAnInvariantIsNotSaved(_ factory: StoreFactory) async throws {
        let store = try factory.make().store
        var work = comic(title: "Bad", pageImage: FileRef("pageImage/x.png"), source: FileRef("source/y.cbz"))
        work.chapters[0].index = 5
        await #expect(throws: EditError.self) { try await store.save(work) }
        #expect(try await store.works(kind: nil).isEmpty)
    }

    @Test(arguments: StoreFactory.all)
    func aCorruptLocalRecordIsReportedNotSilentlyDropped(_ factory: StoreFactory) async throws {
        let fixture = try factory.make()
        try fixture.corruptLocalRecord()
        await #expect {
            try await fixture.store.works(kind: nil)
        } throws: { error in
            if case PersistenceError.corruptRecord = error { true } else { false }
        }
    }
}

/// Behaviour only `LocalLibraryStore` has.
@Suite struct LocalLibraryStoreTests {
    @Test func reportsOfflineUntilICloudSyncExists() async throws {
        let store = try StoreFactory.local.make().store
        var statuses: [SyncStatus] = []
        for await status in store.syncStatus { statuses.append(status) }
        #expect(statuses == [.offline])
    }

    /// A Library made by a build without covers has no folder for them until a store opens it.
    @Test func aLibraryFromBeforeCoversCanStoreOne() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "LibraryStoreTests-\(UUID())")
        _ = try LocalLibraryStore(root: root)
        try FileManager.default.removeItem(at: root.appending(path: "files/cover"))

        let cover = try await LocalLibraryStore(root: root).store(file: tempFile("cover", ext: "jpg"), kind: .cover)

        #expect(try await LocalLibraryStore(root: root).isDownloaded(cover))
    }
}
