import ComicStructure
import Foundation

public enum FileKind: String, Sendable, CaseIterable {
    case source, pageImage, referenceCrop, renderVideo
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
    func store(file: URL, kind: FileKind) async throws -> FileRef
    func evictLocalCopy(_ ref: FileRef) async throws
    var syncStatus: AsyncStream<SyncStatus> { get }
}

/// The Library on this device: one versioned JSON record per Work in `works/`, files in `files/<kind>/`.
// ponytail: local only, so it reports `.offline` and refuses eviction. iCloud sync (CloudKit for records,
// the iCloud Drive container for files) needs the app target's entitlements and lands with the App Shell.
public actor LocalLibraryStore: LibraryStore {
    let root: URL
    private var worksDir: URL { root.appending(path: "works", directoryHint: .isDirectory) }
    private var filesDir: URL { root.appending(path: "files", directoryHint: .isDirectory) }

    public init(root: URL) throws {
        self.root = root
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "works"), withIntermediateDirectories: true)
        for kind in FileKind.allCases {
            try fm.createDirectory(at: root.appending(path: "files/\(kind.rawValue)"), withIntermediateDirectories: true)
        }
    }

    public func works(kind: WorkKind?) async throws -> [Work] {
        let urls = try FileManager.default.contentsOfDirectory(at: worksDir, includingPropertiesForKeys: nil)
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
        try ComicSchema.encode(work).write(to: recordURL(work.id), options: [.atomic, .completeFileProtection])
    }

    public func delete(_ workID: Work.ID) async throws {
        let url = recordURL(workID)
        guard FileManager.default.fileExists(atPath: url.path) else { throw PersistenceError.notFound(workID.uuidString) }
        let work = try ComicSchema.decode(Data(contentsOf: url))
        // Record first: a failure part-way leaves orphaned files, never a Work pointing at missing files.
        try FileManager.default.removeItem(at: url)
        for ref in work.fileRefs {
            let file = try localURL(ref)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }

    public func fileURL(for ref: FileRef) async throws -> URL {
        let url = try localURL(ref)
        guard FileManager.default.fileExists(atPath: url.path) else { throw PersistenceError.notFound(ref.id) }
        return url
    }

    public func store(file: URL, kind: FileKind) async throws -> FileRef {
        let ext = file.pathExtension.lowercased()
        let ref = FileRef("\(kind.rawValue)/\(UUID().uuidString)" + (ext.isEmpty ? "" : ".\(ext)"))
        try FileManager.default.copyItem(at: file, to: try localURL(ref))
        return ref
    }

    public func evictLocalCopy(_ ref: FileRef) async throws {
        _ = try await fileURL(for: ref)
        throw PersistenceError.notSafelyInCloud(ref)
    }

    public nonisolated var syncStatus: AsyncStream<SyncStatus> {
        AsyncStream { $0.yield(.offline); $0.finish() }
    }

    private func recordURL(_ id: UUID) -> URL { worksDir.appending(path: "\(id.uuidString).json") }

    /// Resolves a FileRef strictly: `<kind>/<uuid>` with an optional short alphanumeric extension.
    private func localURL(_ ref: FileRef) throws -> URL {
        let parts = ref.id.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, FileKind(rawValue: String(parts[0])) != nil else { throw PersistenceError.invalidFileRef(ref.id) }
        let name = parts[1].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard UUID(uuidString: String(name[0])) != nil,
              name.count == 1 || (1...10).contains(name[1].count) && name[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { throw PersistenceError.invalidFileRef(ref.id) }
        return filesDir.appending(path: ref.id)
    }
}

extension Work {
    /// Every file this Work references.
    var fileRefs: Set<FileRef> {
        var refs = Set(sources.map(\.fileRef))
        refs.formUnion(chapters.flatMap(\.pages).map(\.imageRef))
        refs.formUnion(cast.characters.flatMap(\.referenceCrops))
        refs.formUnion(renders.compactMap(\.videoRef))
        return refs
    }
}
