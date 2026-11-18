import ComicStructure
import Foundation
@testable import Persistence

/// An in-memory private record database with a change feed, like one CloudKit zone: every save or delete
/// gets the next position in the feed, and a token is the position read up to.
actor FakeRecordSyncBackend: RecordSyncBackend {
    private enum Entry { case record(WorkRecord), tombstone(Tombstone) }
    private var records: [Work.ID: (entry: Entry, position: UInt64)] = [:]
    private var position: UInt64 = 0
    /// Runs inside `save` before the records land, as if the upload were still in flight.
    private var whileUploading: (@Sendable () async -> Void)?

    func onUpload(_ hook: @escaping @Sendable () async -> Void) { whileUploading = hook }

    func fetchChanges(since token: ChangeToken?) async throws -> RecordChanges {
        let after = token.map { $0.rawValue.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) } } ?? 0
        let entries = records.values.filter { $0.position > after }.sorted { $0.position < $1.position }.map(\.entry)
        return RecordChanges(
            changed: entries.compactMap { if case .record(let r) = $0 { r } else { nil } },
            deleted: entries.compactMap { if case .tombstone(let t) = $0 { t } else { nil } },
            token: ChangeToken(rawValue: withUnsafeBytes(of: position) { Data($0) }))
    }

    func save(_ records: [WorkRecord]) async throws {
        if let hook = whileUploading { whileUploading = nil; await hook() }
        for record in records {
            position += 1
            self.records[record.workID] = (.record(record), position)
        }
    }

    func delete(_ tombstones: [Tombstone]) async throws {
        for tombstone in tombstones {
            position += 1
            records[tombstone.workID] = (.tombstone(tombstone), position)
        }
    }

    /// Every live (not deleted) record the service holds, for asserting what was uploaded.
    var all: [WorkRecord] { records.values.compactMap { if case .record(let r) = $0.entry { r } else { nil } } }
}

/// An in-memory iCloud Drive container. Copied-in files count as uploaded at once unless uploads are held.
actor FakeUbiquitousFileContainer: UbiquitousFileContainer {
    private var files: [FileRef: Data] = [:]
    private var uploading: Set<FileRef> = []
    private var holdingUploads = false

    /// From now on, copied-in files stay "uploading": readable on this device, not yet in iCloud.
    func holdUploads() { holdingUploads = true }

    func copyIn(_ local: URL, as ref: FileRef) async throws {
        files[ref] = try Data(contentsOf: local)
        if holdingUploads { uploading.insert(ref) }
    }

    func download(_ ref: FileRef, to local: URL) async throws {
        guard let data = files[ref] else { throw PersistenceError.notFound(ref.id) }
        try data.write(to: local)
    }

    func isUploaded(_ ref: FileRef) async throws -> Bool { files[ref] != nil && !uploading.contains(ref) }

    func remove(_ ref: FileRef) async throws { files[ref] = nil }

    /// Every file the container holds, for asserting what was uploaded or removed.
    var all: Set<FileRef> { Set(files.keys) }
}

/// Two devices sharing one iCloud account: each has its own local Library, both share one record database
/// and one file container.
struct TwoDevices {
    let records = FakeRecordSyncBackend()
    let files = FakeUbiquitousFileContainer()
    let rootA = FileManager.default.temporaryDirectory.appending(path: "DeviceA-\(UUID())")
    let rootB = FileManager.default.temporaryDirectory.appending(path: "DeviceB-\(UUID())")
    let a: CloudLibraryStore
    let b: CloudLibraryStore

    init() throws {
        a = try CloudLibraryStore(root: rootA, records: records, files: files)
        b = try CloudLibraryStore(root: rootB, records: records, files: files)
    }

    /// Device A relaunched: a new store on A's Library.
    func reopenA() throws -> CloudLibraryStore { try CloudLibraryStore(root: rootA, records: records, files: files) }
}
