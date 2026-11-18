import ComicStructure
import Foundation
import Synchronization

/// The Library on this device, synced through the user's iCloud: Work records through a `RecordSyncBackend`,
/// files through a `UbiquitousFileContainer`.
public actor CloudLibraryStore: LibraryStore {
    private let local: LocalLibraryStore
    private let records: any RecordSyncBackend
    private let files: any UbiquitousFileContainer
    /// Local writes not yet uploaded; kept on disk so they survive a relaunch. Change it only through `updateOutbox`.
    private var outbox: Outbox
    private let outboxURL: URL
    private let status: StatusFeed
    /// When each Work this device knows was deleted was deleted; a save no later than that is dropped.
    /// Kept on disk; change it only through `recordDeletion`.
    private var deletions: [Work.ID: Date]
    private let deletionsURL: URL
    /// Where this device has read the record feed up to.
    private var token: ChangeToken?

    public init(root: URL, records: any RecordSyncBackend, files: any UbiquitousFileContainer) throws {
        local = try LocalLibraryStore(root: root)
        self.records = records
        self.files = files
        outboxURL = root.appending(path: "outbox.json")
        deletionsURL = root.appending(path: "deletions.json")
        outbox = try Self.load(outboxURL) ?? Outbox()
        deletions = try Self.load(deletionsURL) ?? [:]
        status = StatusFeed(outbox.isEmpty ? .synced : .syncing)
    }

    private static func load<T: Decodable>(_ url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: url)) } catch {
            throw PersistenceError.corruptRecord(url.lastPathComponent, underlying: String(describing: error))
        }
    }

    /// Remembers when this Work was deleted.
    private func recordDeletion(_ tombstone: Tombstone) throws {
        deletions[tombstone.workID] = tombstone.deletedAt
        try JSONEncoder().encode(deletions).write(to: deletionsURL, options: [.atomic, .completeFileProtection])
    }

    private func updateOutbox(_ change: (inout Outbox) -> Void) throws {
        change(&outbox)
        try JSONEncoder().encode(outbox).write(to: outboxURL, options: [.atomic, .completeFileProtection])
        status.publish(outbox.isEmpty ? .synced : .syncing)
    }

    public func works(kind: WorkKind?) async throws -> [Work] { try await local.works(kind: kind) }
    /// Drops a save of a deleted Work unless it is later than the delete.
    public func save(_ work: Work) async throws {
        if let deletedAt = deletions[work.id], work.updatedAt <= deletedAt { return }
        try await local.save(work)
        try updateOutbox { $0.queue(work.id) }
    }
    /// Deletes the local copy now and queues the tombstone and the removal of the Work's files from iCloud.
    public func delete(_ workID: Work.ID) async throws {
        let work = try await local.remove(workID)
        // Never earlier than the deleted save, so the tombstone always covers it even with a skewed clock.
        let tombstone = Tombstone(workID: workID, deletedAt: max(Date(), work.updatedAt))
        try recordDeletion(tombstone)
        try updateOutbox { $0.queue(tombstone, removing: work.fileRefs) }
    }
    public func fileURL(for ref: FileRef) async throws -> URL {
        let url = try local.layout.fileURL(ref)
        if !FileManager.default.fileExists(atPath: url.path) { try await files.download(ref, to: url) }
        return url
    }
    public func isDownloaded(_ ref: FileRef) async throws -> Bool { try await local.isDownloaded(ref) }
    public func store(file: URL, kind: FileKind) async throws -> FileRef {
        let ref = try await local.store(file: file, kind: kind)
        try updateOutbox { _ = $0.files.insert(ref) }
        return ref
    }
    /// Drops this device's copy only once iCloud holds the file; `fileURL` downloads it again.
    public func evictLocalCopy(_ ref: FileRef) async throws {
        let url = try local.layout.fileURL(ref)
        guard try await files.isUploaded(ref) else { throw PersistenceError.notSafelyInCloud(ref) }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    /// Brings this device and iCloud up to date: applies remote changes, then uploads queued files and
    /// records (files first, so no uploaded record points at a file iCloud lacks).
    public func sync() async throws {
        let changes = try await records.fetchChanges(since: token)
        for record in changes.changed {
            let queued = outbox.works[record.workID]
            // ponytail: a bad remote record fails the whole sync for now; reporting and skipping it is #9.
            switch try await local.apply(record, deletedAt: deletions[record.workID]) {
            case .applied: try updateOutbox { $0.dequeue(record.workID, ifStill: queued) }
            case .superseded: break
            // An older save replaced the tombstone in iCloud; put the tombstone back so every device drops it.
            case .deleted(let deletedAt):
                try updateOutbox { $0.queue(Tombstone(workID: record.workID, deletedAt: deletedAt), removing: []) }
            }
        }
        // A save the tombstone covers is gone with the local copy, so the upload below finds nothing to send.
        for tombstone in changes.deleted {
            try recordDeletion(tombstone)
            try await local.apply(tombstone)
        }
        token = changes.token

        for ref in outbox.files {
            try await files.copyIn(local.layout.fileURL(ref), as: ref)
            try updateOutbox { _ = $0.files.remove(ref) }
        }
        // A save made while this upload is in flight bumps its generation, so it stays queued for next time.
        let queued = outbox.works
        var upload: [WorkRecord] = []
        for id in queued.keys {
            if let work = try await local.work(id) { upload.append(try WorkRecord(work)) }
        }
        try await records.save(upload)
        try updateOutbox { outbox in
            for (id, generation) in queued { outbox.dequeue(id, ifStill: generation) }
        }

        // Tombstones before removing files, so no live record points at a removed file.
        let tombstones = outbox.tombstones
        try await records.delete(tombstones)
        try updateOutbox { outbox in for tombstone in tombstones { outbox.tombstones.removeAll { $0 == tombstone } } }
        for ref in outbox.removals {
            try await files.remove(ref)
            try updateOutbox { _ = $0.removals.remove(ref) }
        }
    }

    /// `.syncing` while local writes wait to upload, `.synced` once the queue is empty. Each subscriber
    /// gets the current status first, then every change.
    public nonisolated var syncStatus: AsyncStream<SyncStatus> { status.subscribe() }
}

/// What this device still has to upload.
struct Outbox: Codable {
    /// Each queued Work with the generation of its latest save.
    private(set) var works: [Work.ID: UInt64] = [:]
    var files: Set<FileRef> = []
    var tombstones: [Tombstone] = []
    /// Files of deleted Works, to remove from iCloud.
    var removals: Set<FileRef> = []
    private var generation: UInt64 = 0
    var isEmpty: Bool { works.isEmpty && files.isEmpty && tombstones.isEmpty && removals.isEmpty }

    mutating func queue(_ id: Work.ID) {
        generation += 1
        works[id] = generation
    }

    /// Queues a deleted Work's tombstone and file removals in place of its files still waiting to upload.
    mutating func queue(_ tombstone: Tombstone, removing refs: Set<FileRef>) {
        files.subtract(refs)
        tombstones.append(tombstone)
        removals.formUnion(refs)
    }

    /// Removes the Work unless it was saved again since `generation` was read.
    mutating func dequeue(_ id: Work.ID, ifStill generation: UInt64?) {
        if works[id] == generation { works[id] = nil }
    }
}

extension LocalLibraryStore {
    enum Applied: Equatable { case applied, superseded, deleted(at: Date) }

    /// Applies a remote record unless the Work was deleted at or after its `updatedAt` or the local copy beats
    /// it, in one step so no local save lands in between.
    func apply(_ record: WorkRecord, deletedAt: Date?) throws -> Applied {
        // Decide and write from the decoded Work only, never from header fields that may disagree with it.
        let incoming = try WorkRecord(ComicSchema.decode(record.payload))
        if let deletedAt, incoming.updatedAt <= deletedAt { return .deleted(at: deletedAt) }
        if let mine = try work(incoming.workID), try !incoming.supersedes(mine) { return .superseded }
        try incoming.payload.write(to: layout.recordURL(incoming.workID), options: [.atomic, .completeFileProtection])
        return .applied
    }

    /// Deletes the local copy and its files if the tombstone covers it, in one step so no local save lands
    /// in between.
    func apply(_ tombstone: Tombstone) throws {
        guard let mine = try work(tombstone.workID), mine.updatedAt <= tombstone.deletedAt else { return }
        try removeWork(mine)
    }
}

/// The current `SyncStatus`, fanned out to every `syncStatus` subscriber.
final class StatusFeed: Sendable {
    private let state: Mutex<(current: SyncStatus, subscribers: [UUID: AsyncStream<SyncStatus>.Continuation])>

    init(_ initial: SyncStatus) { state = Mutex((initial, [:])) }

    func subscribe() -> AsyncStream<SyncStatus> {
        AsyncStream { continuation in
            let id = UUID()
            state.withLock { state in
                continuation.yield(state.current)
                state.subscribers[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) } }
        }
    }

    func publish(_ status: SyncStatus) {
        state.withLock { state in
            guard state.current != status else { return }
            state.current = status
            for subscriber in state.subscribers.values { subscriber.yield(status) }
        }
    }
}
