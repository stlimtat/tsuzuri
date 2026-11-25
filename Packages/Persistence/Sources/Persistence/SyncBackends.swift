import ComicStructure
import Foundation

/// One Work as the record service holds it: the Work's `ComicSchema` JSON as an asset, plus the fields
/// sync decides on without decoding it.
public struct WorkRecord: Equatable, Sendable {
    public let workID: Work.ID
    public let schemaVersion: Int
    public let updatedAt: Date
    /// The Work's `ComicSchema` JSON. Untrusted: whoever applies it decodes and validates it.
    public let payload: Data

    public init(workID: Work.ID, schemaVersion: Int, updatedAt: Date, payload: Data) {
        self.workID = workID; self.schemaVersion = schemaVersion; self.updatedAt = updatedAt; self.payload = payload
    }

    /// Whole-Work last-writer-wins by `updatedAt` (ADR 0007). A tie goes to the greater payload bytes, so
    /// every device picks the same winner whichever order it sees the two in.
    func supersedes(_ work: Work) throws -> Bool {
        if updatedAt != work.updatedAt { return updatedAt > work.updatedAt }
        return try ComicSchema.encode(work).lexicographicallyPrecedes(payload)
    }

    init(_ work: Work) throws {
        self.init(workID: work.id, schemaVersion: ComicSchema.currentVersion, updatedAt: work.updatedAt,
                  payload: try ComicSchema.encode(work))
    }
}

/// What replaces a deleted Work's record, so every device deletes it and no save from at or before
/// `deletedAt` brings it back (ADR 0007).
public struct Tombstone: Equatable, Sendable, Codable {
    public let workID: Work.ID
    public let deletedAt: Date

    public init(workID: Work.ID, deletedAt: Date) { self.workID = workID; self.deletedAt = deletedAt }
}

/// Where the record feed has been read up to. Opaque: only the backend that issued it understands it.
public struct ChangeToken: Hashable, Sendable, Codable {
    public let rawValue: Data
    public init(rawValue: Data) { self.rawValue = rawValue }
}

/// The records changed and the Works deleted since a token, and the token to ask from next time.
public struct RecordChanges: Sendable {
    public let changed: [WorkRecord]
    public let deleted: [Tombstone]
    public let token: ChangeToken

    public init(changed: [WorkRecord], deleted: [Tombstone] = [], token: ChangeToken) {
        self.changed = changed; self.deleted = deleted; self.token = token
    }
}

/// Why iCloud refused a request. Backends throw these so sync can tell the user and keep everything queued.
public enum ICloudError: Error, Equatable, Sendable {
    /// Signed out of iCloud, iCloud restricted, or no network.
    case accountUnavailable
    /// The user's iCloud storage is full.
    case quotaExceeded
}

/// The user's private record database (live: CloudKit, one custom zone of the private database).
public protocol RecordSyncBackend: Sendable {
    /// Every record changed since `token`; `nil` means from the beginning.
    func fetchChanges(since token: ChangeToken?) async throws -> RecordChanges
    /// Saves the records, each replacing the one held for its Work ID only if it wins whole-Work
    /// last-writer-wins against it (`RemoteEntry.replaces`); a losing save is dropped without an error.
    func save(_ records: [WorkRecord]) async throws
    /// Replaces each Work's record with its tombstone, under the same last-writer-wins as `save`; a losing
    /// tombstone is dropped without an error.
    func delete(_ tombstones: [Tombstone]) async throws
}

/// The app's iCloud Drive container, laid out like `files/` under a Library root: `<kind>/<uuid>[.<ext>]`.
public protocol UbiquitousFileContainer: Sendable {
    /// Copies a local file into the container under `ref`.
    func copyIn(_ local: URL, as ref: FileRef) async throws
    /// Downloads `ref` and writes it to `local`, returning once the file is there.
    func download(_ ref: FileRef, to local: URL) async throws
    /// Whether iCloud holds `ref`, so this device's copy can be dropped without losing it.
    func isUploaded(_ ref: FileRef) async throws -> Bool
    /// Removes `ref` from the container; removing a file it lacks is not an error.
    func remove(_ ref: FileRef) async throws
}
