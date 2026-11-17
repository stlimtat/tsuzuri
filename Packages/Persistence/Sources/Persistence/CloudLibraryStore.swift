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
    /// Where this device has read the record feed up to.
    private var token: ChangeToken?

    public init(root: URL, records: any RecordSyncBackend, files: any UbiquitousFileContainer) throws {
        local = try LocalLibraryStore(root: root)
        self.records = records
        self.files = files
        outboxURL = root.appending(path: "outbox.json")
        if FileManager.default.fileExists(atPath: outboxURL.path) {
            do { outbox = try JSONDecoder().decode(Outbox.self, from: Data(contentsOf: outboxURL)) } catch {
                throw PersistenceError.corruptRecord(outboxURL.lastPathComponent, underlying: String(describing: error))
            }
        } else {
            outbox = Outbox()
        }
        status = StatusFeed(outbox.isEmpty ? .synced : .syncing)
    }

    private func updateOutbox(_ change: (inout Outbox) -> Void) throws {
        change(&outbox)
        try JSONEncoder().encode(outbox).write(to: outboxURL, options: [.atomic, .completeFileProtection])
        status.publish(outbox.isEmpty ? .synced : .syncing)
    }

    public func works(kind: WorkKind?) async throws -> [Work] { try await local.works(kind: kind) }
    public func save(_ work: Work) async throws {
        try await local.save(work)
        try updateOutbox { $0.queue(work.id) }
    }
    // ponytail: local only; tombstones and deleting from iCloud land with #8.
    public func delete(_ workID: Work.ID) async throws { try await local.delete(workID) }
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
    // ponytail: refuses like the local store until the container can say a file is uploaded (#8).
    public func evictLocalCopy(_ ref: FileRef) async throws { try await local.evictLocalCopy(ref) }
    /// Brings this device and iCloud up to date: applies remote changes, then uploads queued files and
    /// records (files first, so no uploaded record points at a file iCloud lacks).
    public func sync() async throws {
        let changes = try await records.fetchChanges(since: token)
        for record in changes.changed {
            let queued = outbox.works[record.workID]
            // ponytail: a bad remote record fails the whole sync for now; reporting and skipping it is #9.
            if try await local.apply(record) { try updateOutbox { $0.dequeue(record.workID, ifStill: queued) } }
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
    private var generation: UInt64 = 0
    var isEmpty: Bool { works.isEmpty && files.isEmpty }

    mutating func queue(_ id: Work.ID) {
        generation += 1
        works[id] = generation
    }

    /// Removes the Work unless it was saved again since `generation` was read.
    mutating func dequeue(_ id: Work.ID, ifStill generation: UInt64?) {
        if works[id] == generation { works[id] = nil }
    }
}

extension LocalLibraryStore {
    /// Applies a remote record if it beats the local copy, in one step so no local save lands in between.
    /// Returns whether it was applied.
    func apply(_ record: WorkRecord) throws -> Bool {
        // Decide and write from the decoded Work only, never from header fields that may disagree with it.
        let incoming = try WorkRecord(ComicSchema.decode(record.payload))
        if let mine = try work(incoming.workID), try !incoming.supersedes(mine) { return false }
        try incoming.payload.write(to: layout.recordURL(incoming.workID), options: [.atomic, .completeFileProtection])
        return true
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
