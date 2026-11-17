import ComicStructure
import Foundation
@testable import Persistence

/// An in-memory private record database with a change feed, like one CloudKit zone: every save gets the
/// next position in the feed, and a token is the position read up to.
actor FakeRecordSyncBackend: RecordSyncBackend {
    private var records: [Work.ID: (record: WorkRecord, position: UInt64)] = [:]
    private var position: UInt64 = 0
    /// Runs inside `save` before the records land, as if the upload were still in flight.
    private var whileUploading: (@Sendable () async -> Void)?

    func onUpload(_ hook: @escaping @Sendable () async -> Void) { whileUploading = hook }

    func fetchChanges(since token: ChangeToken?) async throws -> RecordChanges {
        let after = token.map { $0.rawValue.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) } } ?? 0
        let changed = records.values.filter { $0.position > after }.sorted { $0.position < $1.position }.map(\.record)
        return RecordChanges(changed: changed, token: ChangeToken(rawValue: withUnsafeBytes(of: position) { Data($0) }))
    }

    func save(_ records: [WorkRecord]) async throws {
        if let hook = whileUploading { whileUploading = nil; await hook() }
        for record in records {
            position += 1
            self.records[record.workID] = (record, position)
        }
    }

    /// Every record the service holds, for asserting what was uploaded.
    var all: [WorkRecord] { records.values.map(\.record) }
}

/// An in-memory iCloud Drive container.
actor FakeUbiquitousFileContainer: UbiquitousFileContainer {
    private var files: [FileRef: Data] = [:]

    func copyIn(_ local: URL, as ref: FileRef) async throws {
        files[ref] = try Data(contentsOf: local)
    }

    func download(_ ref: FileRef, to local: URL) async throws {
        guard let data = files[ref] else { throw PersistenceError.notFound(ref.id) }
        try data.write(to: local)
    }
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
