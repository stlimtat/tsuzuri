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
    private let store: any LibraryStore

    init(store: any LibraryStore) { self.store = store }

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

    /// Sets the Work's title and `updatedAt`, then saves it; a blank name changes nothing.
    func rename(_ id: Work.ID, to name: String, at now: Date = Date()) async throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard var work = try await store.works(kind: nil).first(where: { $0.id == id }) else {
            throw PersistenceError.notFound(id.uuidString)
        }
        work.title = name
        work.updatedAt = now
        try await store.save(work)
        try await reload()
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
