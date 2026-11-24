import ComicStructure
import Foundation
import ImageIO
import Observation
import Persistence

/// One Work as the debug Library lists it.
struct DebugLibraryRow: Identifiable, Equatable, Sendable {
    let id: Work.ID
    let name: String
    let pageCount: Int
    /// Pages whose image file is on this device (`LibraryStore.isDownloaded`).
    let downloadedPageCount: Int
}

enum DebugLibraryError: Error, Equatable {
    /// The file given for a sample Page is not a readable image.
    case unreadablePage(URL)
}

/// The debug Library screen's state and actions, using only the public `LibraryStore` seam.
@MainActor @Observable
final class DebugLibraryModel {
    private(set) var rows: [DebugLibraryRow] = []
    /// The store's latest sync status, once `followSyncStatus` has heard one.
    private(set) var syncStatus: SyncStatus?
    /// The banner to show for `syncStatus`, if any.
    var banner: SyncBanner? { syncStatus.flatMap(SyncBanner.init) }
    private let store: any LibraryStore
    private let sync: (@Sendable () async throws -> Void)?

    /// `sync` brings the store up to date with iCloud (`CloudLibraryStore.sync`); nil for a local-only store.
    init(store: any LibraryStore, sync: (@Sendable () async throws -> Void)? = nil) {
        self.store = store
        self.sync = sync
    }

    /// Syncs, then reloads. A failed sync doesn't fail the refresh: the sync status already reports it.
    func refresh() async throws {
        try? await sync?()
        try await reload()
    }

    /// Keeps `syncStatus` up to date until the calling task is cancelled.
    func followSyncStatus() async {
        for await status in store.syncStatus { syncStatus = status }
    }

    /// Reads every Work from the store, in the store's order.
    func reload() async throws {
        var rows: [DebugLibraryRow] = []
        for work in try await store.works(kind: nil) {
            let pages = work.chapters.flatMap(\.pages)
            var downloaded = 0
            for page in pages where try await store.isDownloaded(page.imageRef) { downloaded += 1 }
            rows.append(DebugLibraryRow(id: work.id, name: work.title, pageCount: pages.count, downloadedPageCount: downloaded))
        }
        self.rows = rows
    }

    /// Adds a right-to-left comic Work with one Chapter holding `pageFile` as its only Page.
    func createSampleWork(fromPage pageFile: URL, name: String) async throws {
        let size = try Self.pixelSize(of: pageFile)
        let ref = try await store.store(file: pageFile, kind: .pageImage)
        let page = Page(imageRef: ref, pixelSize: size, index: 0, origin: .sourceEntry(pageFile.lastPathComponent))
        let work = Work(kind: .comic, title: name, readingDirection: .rightToLeft,
                        chapters: [Chapter(title: "1", index: 0, pages: [page])])
        try await store.save(work)
        try await reload()
    }

    /// Sets the Work's title (trimmed) and `updatedAt`, then saves it; a blank name changes nothing.
    func rename(_ id: Work.ID, to name: String, at now: Date = Date()) async throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard var work = try await store.works(kind: nil).first(where: { $0.id == id }) else {
            throw PersistenceError.notFound(id.uuidString)
        }
        work.title = name
        work.updatedAt = now
        try await store.save(work)
        try await reload()
    }

    /// The Work's first Page image, downloaded from iCloud if this device lacks it; the list then shows the
    /// new downloaded count.
    func firstPageFile(of id: Work.ID) async throws -> URL {
        guard let page = try await store.works(kind: nil).first(where: { $0.id == id })?.chapters.first?.pages.first else {
            throw PersistenceError.notFound(id.uuidString)
        }
        let url = try await store.fileURL(for: page.imageRef)
        try await reload()
        return url
    }

    /// Deletes the Work and every file it references.
    func delete(_ id: Work.ID) async throws {
        try await store.delete(id)
        try await reload()
    }

    private static func pixelSize(of file: URL) throws -> PixelSize {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw DebugLibraryError.unreadablePage(file) }
        return PixelSize(width: width, height: height)
    }
}
