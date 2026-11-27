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
    /// What went wrong in the last sync (`.offline`, `.iCloudFull`, or `.error` for another failure or skipped
    /// remote records), or nil; shown in place of `.syncing`/`.synced` until a sync finishes cleanly. Change it only through `report`.
    private var problem: SyncStatus?
    /// When each Work this device knows was deleted was deleted; a save no later than that is dropped.
    /// Kept on disk; change it only through `recordDeletion`.
    private var deletions: [Work.ID: Date]
    private let deletionsURL: URL
    /// Where this device has read the record feed up to. Kept on disk; change it only through `advance`.
    private var token: ChangeToken?
    private let tokenURL: URL
    /// The most recently started sync, which the next one waits for.
    private var lastSync: Task<Void, Error>?
    /// Times the waits between sync retries.
    private let clock: any Clock<Duration>
    /// Resumes `keepSynced` from its current wait; numbered so a stale retry timer can't end a later wait.
    private var wakeUp: CheckedContinuation<Void, Never>?
    private var waitID = 0
    /// A `requestSync` that came while no wait was in progress, so the next one ends at once.
    private var syncRequested = false

    public init(root: URL, records: any RecordSyncBackend, files: any UbiquitousFileContainer,
                clock: any Clock<Duration> = ContinuousClock()) throws {
        self.clock = clock
        local = try LocalLibraryStore(root: root)
        self.records = records
        self.files = files
        outboxURL = root.appending(path: "outbox.json")
        deletionsURL = root.appending(path: "deletions.json")
        tokenURL = root.appending(path: "change-token.json")
        // A corrupt outbox throws rather than reporting `.error` and starting empty, which would silently never
        // upload the writes it held. ponytail: rebuild it instead (queue every local Work and file) if it happens.
        outbox = try Self.load(outboxURL) ?? Outbox()
        deletions = try Self.load(deletionsURL) ?? [:]
        // A corrupt token only costs a fetch from the start.
        token = (try? Self.load(tokenURL)) ?? nil
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

    /// Remembers that every change up to `token` is applied locally.
    private func advance(to token: ChangeToken) throws {
        self.token = token
        try JSONEncoder().encode(token).write(to: tokenURL, options: [.atomic, .completeFileProtection])
    }

    private func updateOutbox(_ change: (inout Outbox) -> Void) throws {
        change(&outbox)
        try JSONEncoder().encode(outbox).write(to: outboxURL, options: [.atomic, .completeFileProtection])
        publishStatus()
    }

    private func report(_ problem: SyncStatus?) {
        self.problem = problem
        publishStatus()
    }

    private func publishStatus() { status.publish(problem ?? (outbox.isEmpty ? .synced : .syncing)) }

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
    /// Deletes the local copy now and queues the removal from iCloud, which replaces the upload if that hasn't run.
    public func removeFile(_ ref: FileRef) async throws {
        try await local.removeFile(ref)
        try updateOutbox { $0.queueRemoval(of: [ref]) }
    }
    /// Brings this device and iCloud up to date: applies remote changes, then uploads queued files and
    /// records (files first, so no uploaded record points at a file iCloud lacks).
    /// Throws when iCloud is unreachable or refuses the upload; whatever didn't upload stays queued. A failure
    /// other than `ICloudError` is reported as `.error` with its description. A remote
    /// record that fails `verified()` is skipped and reported as `.error`, not thrown. A sync
    /// called while another runs starts once that one ends.
    public func sync() async throws {
        let previous = lastSync
        let pass = Task {
            _ = await previous?.result
            try await syncAndReport()
        }
        lastSync = pass
        try await pass.value
    }

    private func syncAndReport() async throws {
        do {
            let rejected = try await syncOnce()
            report(rejected.isEmpty ? nil : .error("Skipped \(rejected.count) bad record(s) from iCloud: " + rejected.joined(separator: "; ")))
        } catch let error as ICloudError {
            report(error == .accountUnavailable ? .offline : .iCloudFull)
            throw error
        } catch {
            report(.error(String(describing: error)))
            throw error
        }
    }

    /// One pass; returns why each remote record it skipped was rejected.
    private func syncOnce() async throws -> [String] {
        let changes = try await records.fetchChanges(since: token)
        var rejected: [String] = []
        for remote in changes.changed {
            // Untrusted: a bad record is skipped, leaving the local copy alone and the rest of the batch going.
            let record: WorkRecord
            do { record = try remote.verified() } catch {
                rejected.append("Work \(remote.workID): \(error)")
                continue
            }
            let queued = outbox.works[record.workID]
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
        try advance(to: changes.token)

        for ref in outbox.files {
            // A queued file is gone from disk only because it was removed while this sync awaited, or its Work
            // was deleted by a tombstone applied above or here meanwhile. Nothing to upload, so it just leaves the queue.
            let url = try local.layout.fileURL(ref)
            if FileManager.default.fileExists(atPath: url.path) { try await files.copyIn(url, as: ref) }
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
        return rejected
    }

    /// Syncs now, then again on every `requestSync`; after a failure it retries on its own, backing off
    /// (`retryDelay`). Runs until its task is cancelled; run one at a time.
    public func keepSynced() async {
        var failures = 0
        while !Task.isCancelled {
            do {
                try await sync()
                failures = 0
            } catch { failures += 1 }
            await wait(upTo: failures == 0 ? nil : Self.retryDelay(afterFailures: failures))
        }
    }

    /// Asks `keepSynced` to sync now, cutting short any retry wait. Call it on launch, on an iCloud account
    /// change, and when iCloud says records changed.
    public func requestSync() {
        if let wakeUp {
            self.wakeUp = nil
            wakeUp.resume()
        } else {
            syncRequested = true
        }
    }

    /// Waits for a `requestSync`, or until `delay` has passed on `clock`.
    private func wait(upTo delay: Duration?) async {
        if syncRequested {
            syncRequested = false
            return
        }
        waitID += 1
        let id = waitID
        let timer = delay.map { delay in
            Task { [clock] in
                guard (try? await clock.sleep(for: delay)) != nil else { return }
                await self.endWait(id)
            }
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { wakeUp = $0 }
        } onCancel: {
            Task { await self.requestSync() }
        }
        timer?.cancel()
    }

    /// Ends wait `id` if it is still the one in progress.
    private func endWait(_ id: Int) {
        guard id == waitID, let wakeUp else { return }
        self.wakeUp = nil
        wakeUp.resume()
    }

    /// 10 s after the first failure, doubling each time, never more than 15 minutes.
    static func retryDelay(afterFailures failures: Int) -> Duration {
        min(.seconds(10) * (1 << min(failures - 1, 10)), .seconds(15 * 60))
    }

    /// `.syncing` while local writes wait to upload, `.synced` once the queue is empty; `.offline` or
    /// `.iCloudFull` while iCloud can't take the queue, and `.error` after a sync failed otherwise or skipped
    /// bad remote records, until a sync finishes cleanly. Each subscriber gets the current status first, then every change.
    public nonisolated var syncStatus: AsyncStream<SyncStatus> { status.subscribe() }
}

/// What this device still has to upload.
struct Outbox: Codable {
    /// Each queued Work with the generation of its latest save.
    private(set) var works: [Work.ID: UInt64] = [:]
    var files: Set<FileRef> = []
    var tombstones: [Tombstone] = []
    /// Files to remove from iCloud: those of deleted Works, and those `removeFile` was given.
    var removals: Set<FileRef> = []
    private var generation: UInt64 = 0
    var isEmpty: Bool { works.isEmpty && files.isEmpty && tombstones.isEmpty && removals.isEmpty }

    mutating func queue(_ id: Work.ID) {
        generation += 1
        works[id] = generation
    }

    /// Queues a deleted Work's tombstone and the removal of its files.
    mutating func queue(_ tombstone: Tombstone, removing refs: Set<FileRef>) {
        tombstones.append(tombstone)
        queueRemoval(of: refs)
    }

    /// Queues the files' removal from iCloud in place of any upload of them still waiting.
    mutating func queueRemoval(of refs: Set<FileRef>) {
        files.subtract(refs)
        removals.formUnion(refs)
    }

    /// Removes the Work unless it was saved again since `generation` was read.
    mutating func dequeue(_ id: Work.ID, ifStill generation: UInt64?) {
        if works[id] == generation { works[id] = nil }
    }
}

extension WorkRecord {
    /// The record rebuilt from its decoded Work alone, so no header field that disagrees with the payload is
    /// trusted; throws if the payload isn't a valid `ComicSchema` Work or any FileRef in it fails `validate()`.
    func verified() throws -> WorkRecord {
        let work = try ComicSchema.decode(payload)
        for ref in work.fileRefs { try ref.validate() }
        return try WorkRecord(work)
    }
}

extension LocalLibraryStore {
    enum Applied: Equatable { case applied, superseded, deleted(at: Date) }

    /// Applies a `verified()` remote record unless the Work was deleted at or after its `updatedAt` or the local
    /// copy beats it, in one step so no local save lands in between.
    func apply(_ incoming: WorkRecord, deletedAt: Date?) throws -> Applied {
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
