import ComicStructure
import Foundation
import Testing
@testable import Persistence

@Suite struct LocalLibraryStoreTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "LibraryStoreTests-\(UUID())")

    func makeStore() throws -> LocalLibraryStore { try LocalLibraryStore(root: root) }

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

    @Test func savedWorksAreReadBackFilteredByKind() async throws {
        let store = try makeStore()
        let comicWork = comic(title: "Comic", pageImage: FileRef("pageImage/x.png"), source: FileRef("source/y.cbz"))
        let book = Work(kind: .book, title: "Book", readingDirection: .leftToRight)
        try await store.save(comicWork)
        try await store.save(book)

        #expect(Set(try await store.works(kind: nil)) == [comicWork, book])
        #expect(try await store.works(kind: .book) == [book])
        // A second store on the same directory sees the same Library (survives relaunch).
        #expect(try await LocalLibraryStore(root: root).works(kind: .comic) == [comicWork])
    }

    @Test func savingAgainReplacesTheWork() async throws {
        let store = try makeStore()
        var work = Work(kind: .book, title: "Old", readingDirection: .leftToRight)
        try await store.save(work)
        work.title = "New"
        try await store.save(work)
        #expect(try await store.works(kind: nil).map(\.title) == ["New"])
    }

    @Test func storedFilesResolveToTheirContents() async throws {
        let store = try makeStore()
        let ref = try await store.store(file: tempFile("image", ext: "png"), kind: .pageImage)
        #expect(ref.id.hasPrefix("pageImage/") && ref.id.hasSuffix(".png"))
        let url = try await store.fileURL(for: ref)
        #expect(try String(contentsOf: url, encoding: .utf8) == "image")
    }

    @Test func deletingAWorkRemovesItsRecordAndFiles() async throws {
        let store = try makeStore()
        let image = try await store.store(file: tempFile("i", ext: "png"), kind: .pageImage)
        let source = try await store.store(file: tempFile("s", ext: "cbz"), kind: .source)
        let other = try await store.store(file: tempFile("o", ext: "png"), kind: .pageImage)
        let work = comic(title: "Gone", pageImage: image, source: source)
        let kept = comic(title: "Kept", pageImage: other, source: other)
        try await store.save(work)
        try await store.save(kept)

        try await store.delete(work.id)

        #expect(try await store.works(kind: nil) == [kept])
        await #expect(throws: PersistenceError.self) { try await store.fileURL(for: image) }
        await #expect(throws: PersistenceError.self) { try await store.fileURL(for: source) }
        _ = try await store.fileURL(for: other)
    }

    @Test func fileRefsCannotEscapeTheLibrary() async throws {
        let store = try makeStore()
        for id in ["../../etc/passwd", "pageImage/../../x.png", "/etc/passwd", "nope/\(UUID()).png", "pageImage/notauuid.png", "pageImage/\(UUID()).p/g"] {
            await #expect(throws: PersistenceError.invalidFileRef(id)) { try await store.fileURL(for: FileRef(id)) }
        }
    }

    @Test func evictionNeverDropsTheOnlyCopy() async throws {
        let store = try makeStore()
        let ref = try await store.store(file: tempFile("r", ext: "mp4"), kind: .renderVideo)
        await #expect(throws: PersistenceError.notSafelyInCloud(ref)) { try await store.evictLocalCopy(ref) }
        _ = try await store.fileURL(for: ref)
    }

    @Test func reportsOfflineUntilICloudSyncExists() async throws {
        let store = try makeStore()
        var statuses: [SyncStatus] = []
        for await status in store.syncStatus { statuses.append(status) }
        #expect(statuses == [.offline])
    }

    @Test func aWorkThatBreaksAnInvariantIsNotSaved() async throws {
        let store = try makeStore()
        var work = comic(title: "Bad", pageImage: FileRef("pageImage/x.png"), source: FileRef("source/y.cbz"))
        work.chapters[0].index = 5
        await #expect(throws: EditError.self) { try await store.save(work) }
        #expect(try await store.works(kind: nil).isEmpty)
    }

    @Test func aCorruptRecordIsReportedNotSilentlyDropped() async throws {
        let store = try makeStore()
        try Data("{".utf8).write(to: root.appending(path: "works/\(UUID()).json"))
        await #expect(throws: PersistenceError.self) { try await store.works(kind: nil) }
    }
}
