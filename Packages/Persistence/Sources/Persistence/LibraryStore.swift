import ComicStructure
import Foundation

public enum FileKind: String, Sendable, CaseIterable {
    case source, pageImage, referenceCrop, renderVideo
    /// A book's cover thumbnail for the Library, extracted from its EPUB (which is a `source`).
    case cover
}

public enum SyncStatus: Equatable, Sendable {
    case synced, syncing, offline, iCloudFull
    case error(String)
}

public enum PersistenceError: Error, Equatable, Sendable {
    case notFound(String)
    /// A FileRef that is not `<kind>/<uuid>[.<ext>]`, e.g. a path-traversal attempt from a tampered record.
    case invalidFileRef(String)
    /// The file has no copy in iCloud, so evicting the local copy would lose it.
    case notSafelyInCloud(FileRef)
    /// A stored record could not be decoded; it is left on disk untouched.
    case corruptRecord(String, underlying: String)
}

public protocol LibraryStore: Sendable {
    func works(kind: WorkKind?) async throws -> [Work]
    func save(_ work: Work) async throws
    /// Deletes the Work's record and every file it references.
    func delete(_ workID: Work.ID) async throws
    /// Downloads the file first if only iCloud has it.
    func fileURL(for ref: FileRef) async throws -> URL
    /// Whether the file is on this device, so it opens without downloading.
    func isDownloaded(_ ref: FileRef) async throws -> Bool
    func store(file: URL, kind: FileKind) async throws -> FileRef
    func evictLocalCopy(_ ref: FileRef) async throws
    var syncStatus: AsyncStream<SyncStatus> { get }
}

/// The Library on this device: one versioned JSON record per Work in `works/`, files in `files/<kind>/`.
// Local only, so it reports `.offline` and refuses eviction; `CloudLibraryStore` is the synced Library.
public actor LocalLibraryStore: LibraryStore {
    let layout: LibraryLayout

    public init(root: URL) throws {
        layout = LibraryLayout(root: root)
        try layout.createDirectories()
    }

    public func works(kind: WorkKind?) async throws -> [Work] {
        let urls = try FileManager.default.contentsOfDirectory(at: layout.worksDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let works = try urls.map { url in
            do { return try ComicSchema.decode(Data(contentsOf: url)) } catch {
                throw PersistenceError.corruptRecord(url.lastPathComponent, underlying: String(describing: error))
            }
        }
        return works.filter { kind == nil || $0.kind == kind }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Rejects a Work that breaks an invariant, so one bad save can't make the Library unreadable.
    public func save(_ work: Work) async throws {
        try Invariants.validate(work)
        try ComicSchema.encode(work).write(to: layout.recordURL(work.id), options: [.atomic, .completeFileProtection])
    }

    /// The Work with this ID, or nil if the Library has none.
    func work(_ id: Work.ID) throws -> Work? {
        let url = layout.recordURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try ComicSchema.decode(Data(contentsOf: url)) } catch {
            throw PersistenceError.corruptRecord(url.lastPathComponent, underlying: String(describing: error))
        }
    }

    public func delete(_ workID: Work.ID) async throws { _ = try remove(workID) }

    /// Deletes the Work and its files, returning what was deleted.
    func remove(_ workID: Work.ID) throws -> Work {
        guard let work = try work(workID) else { throw PersistenceError.notFound(workID.uuidString) }
        try removeWork(work)
        return work
    }

    /// Removes the Work's record, then every file it references.
    func removeWork(_ work: Work) throws {
        // Record first: a failure part-way leaves orphaned files, never a Work pointing at missing files.
        try FileManager.default.removeItem(at: layout.recordURL(work.id))
        for ref in work.fileRefs {
            let file = try layout.fileURL(ref)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }

    public func fileURL(for ref: FileRef) async throws -> URL {
        let url = try layout.fileURL(ref)
        guard FileManager.default.fileExists(atPath: url.path) else { throw PersistenceError.notFound(ref.id) }
        return url
    }

    public func isDownloaded(_ ref: FileRef) async throws -> Bool {
        FileManager.default.fileExists(atPath: try layout.fileURL(ref).path)
    }

    public func store(file: URL, kind: FileKind) async throws -> FileRef {
        let ext = file.pathExtension.lowercased()
        let ref = FileRef("\(kind.rawValue)/\(UUID().uuidString)" + (ext.isEmpty ? "" : ".\(ext)"))
        try FileManager.default.copyItem(at: file, to: try layout.fileURL(ref))
        return ref
    }

    public func evictLocalCopy(_ ref: FileRef) async throws {
        _ = try await fileURL(for: ref)
        throw PersistenceError.notSafelyInCloud(ref)
    }

    public nonisolated var syncStatus: AsyncStream<SyncStatus> {
        AsyncStream { $0.yield(.offline); $0.finish() }
    }
}
