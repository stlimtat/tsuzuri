import ComicStructure
import Foundation
import Synchronization
@testable import Persistence

/// An in-memory private record database with a change feed, like one CloudKit zone: every save or delete
/// gets the next position in the feed, and a token is the position read up to. Like CloudKit's conditional
/// save, a write that loses last-writer-wins to what the zone holds is dropped.
actor FakeRecordSyncBackend: RecordSyncBackend {
    private typealias Entry = RemoteEntry
    private var records: [Work.ID: (entry: Entry, position: UInt64)] = [:]
    private var position: UInt64 = 0
    /// Runs inside `save` before the records land, as if the upload were still in flight.
    private var whileUploading: (@Sendable () async -> Void)?

    func onUpload(_ hook: @escaping @Sendable () async -> Void) { whileUploading = hook }

    /// The token each fetch asked from, in order.
    private(set) var fetchedSince: [ChangeToken?] = []
    /// The token each fetch returned, in order.
    private(set) var issued: [ChangeToken] = []

    func fetchChanges(since token: ChangeToken?) async throws -> RecordChanges {
        fetchedSince.append(token)
        let after = token.map { $0.rawValue.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) } } ?? 0
        let entries = records.values.filter { $0.position > after }.sorted { $0.position < $1.position }.map(\.entry)
        let token = ChangeToken(rawValue: withUnsafeBytes(of: position) { Data($0) })
        issued.append(token)
        return RecordChanges(
            changed: entries.compactMap { if case .record(let r) = $0 { r } else { nil } },
            deleted: entries.compactMap { if case .tombstone(let t) = $0 { t } else { nil } },
            token: token)
    }

    /// How many records have been uploaded, counting each upload of the same Work.
    private(set) var uploads = 0

    func save(_ records: [WorkRecord]) async throws {
        if let hook = whileUploading { whileUploading = nil; await hook() }
        uploads += records.count
        for record in records { write(.record(record), for: record.workID) }
    }

    func delete(_ tombstones: [Tombstone]) async throws {
        for tombstone in tombstones { write(.tombstone(tombstone), for: tombstone.workID) }
    }

    private func write(_ entry: Entry, for id: Work.ID) {
        if let held = records[id]?.entry, !entry.replaces(held) { return }
        position += 1
        records[id] = (entry, position)
    }

    /// Every live (not deleted) record the service holds, for asserting what was uploaded.
    var all: [WorkRecord] { records.values.compactMap { if case .record(let r) = $0.entry { r } else { nil } } }
}

/// An in-memory iCloud Drive container. Copied-in files count as uploaded at once unless uploads are held.
actor FakeUbiquitousFileContainer: UbiquitousFileContainer {
    private var files: [FileRef: Data] = [:]
    private var uploading: Set<FileRef> = []
    private var holdingUploads = false

    private var refusingRemovals = false
    /// Runs inside the next `copyIn`, after the file is read and before it lands, as if the upload were in flight.
    private var whileCopyingIn: (@Sendable () async -> Void)?

    func onCopyIn(_ hook: @escaping @Sendable () async -> Void) { whileCopyingIn = hook }

    /// From now on, copied-in files stay "uploading": readable on this device, not yet in iCloud.
    func holdUploads() { holdingUploads = true }
    /// Makes `remove` fail as if the account dropped just then, or stops it failing.
    func refuseRemovals(_ refuse: Bool) { refusingRemovals = refuse }

    func copyIn(_ local: URL, as ref: FileRef) async throws {
        let data = try Data(contentsOf: local)
        if let hook = whileCopyingIn { whileCopyingIn = nil; await hook() }
        files[ref] = data
        if holdingUploads { uploading.insert(ref) }
    }

    func download(_ ref: FileRef, to local: URL) async throws {
        guard let data = files[ref] else { throw PersistenceError.notFound(ref.id) }
        try data.write(to: local)
    }

    func isUploaded(_ ref: FileRef) async throws -> Bool { files[ref] != nil && !uploading.contains(ref) }

    func remove(_ ref: FileRef) async throws {
        if refusingRemovals { throw ICloudError.accountUnavailable }
        files[ref] = nil
    }

    /// Every file the container holds, for asserting what was uploaded or removed.
    var all: Set<FileRef> { Set(files.keys) }
}

/// A clock that moves only when the test advances it. Each `sleep` is announced on `sleeps` with its duration.
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        let offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }
    private struct Sleeper { let deadline: Instant; let wake: CheckedContinuation<Void, Error> }
    private let state = Mutex((now: Instant(offset: .zero), sleepers: [UUID: Sleeper]()))
    private let announce: AsyncStream<Duration>.Continuation
    /// The duration of every sleep started on this clock, in order.
    let sleeps: AsyncStream<Duration>

    init() { (sleeps, announce) = AsyncStream.makeStream() }

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (wake: CheckedContinuation<Void, Error>) in
                let (now, waiting) = state.withLock { state in
                    let waiting = !Task.isCancelled && state.now < deadline
                    if waiting { state.sleepers[id] = Sleeper(deadline: deadline, wake: wake) }
                    return (state.now, waiting)
                }
                announce.yield(now.duration(to: deadline))
                if !waiting { Task.isCancelled ? wake.resume(throwing: CancellationError()) : wake.resume() }
            }
        } onCancel: {
            state.withLock { $0.sleepers.removeValue(forKey: id) }?.wake.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and wakes every sleep whose deadline has passed.
    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in due.keys { state.sleepers[id] = nil }
            return due.values
        }
        for sleeper in due { sleeper.wake.resume() }
    }
}

/// Holds a value set in one task and read in another.
actor Box<Value: Sendable> {
    var value: Value?
    func set(_ new: Value) { value = new }
}

/// One device's view of the iCloud account: signed in with space, signed out, or full.
final class FakeAccount: Sendable {
    enum State { case available, unavailable, full }
    private let state = Mutex(State.available)

    func set(_ new: State) { state.withLock { $0 = new } }

    /// Throws the way iCloud does when the account can't take this request; `writes` adds data to iCloud.
    func check(writes: Bool) throws {
        switch state.withLock({ $0 }) {
        case .available: break
        case .unavailable: throw ICloudError.accountUnavailable
        case .full: if writes { throw ICloudError.quotaExceeded }
        }
    }
}

/// The shared record database as one device reaches it, through that device's account.
struct DeviceRecords: RecordSyncBackend {
    let shared: FakeRecordSyncBackend
    let account: FakeAccount

    func fetchChanges(since token: ChangeToken?) async throws -> RecordChanges {
        try account.check(writes: false)
        return try await shared.fetchChanges(since: token)
    }
    func save(_ records: [WorkRecord]) async throws {
        try account.check(writes: true)
        try await shared.save(records)
    }
    func delete(_ tombstones: [Tombstone]) async throws {
        try account.check(writes: false)
        try await shared.delete(tombstones)
    }
}

/// The shared file container as one device reaches it, through that device's account.
struct DeviceFiles: UbiquitousFileContainer {
    let shared: FakeUbiquitousFileContainer
    let account: FakeAccount

    func copyIn(_ local: URL, as ref: FileRef) async throws {
        try account.check(writes: true)
        try await shared.copyIn(local, as: ref)
    }
    func download(_ ref: FileRef, to local: URL) async throws {
        try account.check(writes: false)
        try await shared.download(ref, to: local)
    }
    func isUploaded(_ ref: FileRef) async throws -> Bool { try await shared.isUploaded(ref) }
    func remove(_ ref: FileRef) async throws {
        try account.check(writes: false)
        try await shared.remove(ref)
    }
}

/// Two devices sharing one iCloud account: each has its own local Library, both share one record database
/// and one file container, and each reaches them through its own `FakeAccount`.
struct TwoDevices {
    let records = FakeRecordSyncBackend()
    let files = FakeUbiquitousFileContainer()
    let accountA = FakeAccount()
    let accountB = FakeAccount()
    /// Device A's clock, which drives its sync retries.
    let clock = ManualClock()
    let rootA = FileManager.default.temporaryDirectory.appending(path: "DeviceA-\(UUID())")
    let rootB = FileManager.default.temporaryDirectory.appending(path: "DeviceB-\(UUID())")
    let a: CloudLibraryStore
    let b: CloudLibraryStore

    init() throws {
        a = try CloudLibraryStore(root: rootA, records: DeviceRecords(shared: records, account: accountA),
                                  files: DeviceFiles(shared: files, account: accountA), clock: clock)
        b = try CloudLibraryStore(root: rootB, records: DeviceRecords(shared: records, account: accountB),
                                  files: DeviceFiles(shared: files, account: accountB))
    }

    /// Device A relaunched: a new store on A's Library.
    func reopenA() throws -> CloudLibraryStore {
        try CloudLibraryStore(root: rootA, records: DeviceRecords(shared: records, account: accountA),
                              files: DeviceFiles(shared: files, account: accountA))
    }
}
