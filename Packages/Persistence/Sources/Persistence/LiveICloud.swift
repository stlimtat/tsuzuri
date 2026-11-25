import CloudKit
import Foundation

/// Where the live backends find the user's iCloud: the app's own container, the private database and one
/// custom record zone. Which CloudKit environment (development or production) is not chosen here: the
/// `com.apple.developer.icloud-container-environment` entitlement decides it per build configuration.
public struct LiveICloudConfiguration: Equatable, Sendable {
    public let containerIdentifier: String
    public let databaseScope: CKDatabase.Scope
    public let zoneName: String

    public static func make(bundleIdentifier: String) -> LiveICloudConfiguration {
        LiveICloudConfiguration(containerIdentifier: "iCloud.\(bundleIdentifier)", databaseScope: .private, zoneName: "Library")
    }
}

/// What the live record backend does about an error from CloudKit.
enum CloudKitRecovery: Equatable {
    /// Give up on this request and tell sync why; everything stays queued for the next try.
    case fail(ICloudError)
    /// The zone is gone (first use, or the user deleted the app's iCloud data): create it and try again.
    case recreateZone
    /// The change token is too old: fetch every change from the start.
    case refetchFromStart
    /// The record changed on the server since this device read it: resolve with last-writer-wins and retry.
    case resolveConflict
    /// Not something sync can recover from; passed on as it is.
    case passOn

    init(_ error: any Error) {
        guard let error = error as? CKError else { self = .passOn; return }
        switch error.code {
        case .notAuthenticated, .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .accountTemporarilyUnavailable:
            self = .fail(.accountUnavailable)
        case .quotaExceeded: self = .fail(.quotaExceeded)
        case .zoneNotFound, .userDeletedZone: self = .recreateZone
        case .changeTokenExpired: self = .refetchFromStart
        case .serverRecordChanged: self = .resolveConflict
        case .partialFailure:
            let cause = error.partialErrorsByItemID?.values.first { ($0 as? CKError)?.code != .batchRequestFailed }
            self = cause.map(CloudKitRecovery.init) ?? .passOn
        default: self = .passOn
        }
    }
}

/// A Work as one CloudKit record of type `Work`, named by the Work ID: its `WorkRecord` (`schemaVersion`,
/// `updatedAt`, and the `ComicSchema` JSON as the `payload` asset) or, once deleted, its tombstone (`deletedAt`).
enum RemoteEntry: Equatable {
    case record(WorkRecord)
    case tombstone(Tombstone)

    static let recordType = "Work"

    var workID: UUID {
        switch self {
        case .record(let record): record.workID
        case .tombstone(let tombstone): tombstone.workID
        }
    }

    /// Reads a fetched CloudKit record. Untrusted: sync verifies the payload before applying it.
    init(_ ckRecord: CKRecord) throws {
        guard let workID = UUID(uuidString: ckRecord.recordID.recordName) else { throw BadRecordName(name: ckRecord.recordID.recordName) }
        if let deletedAt = ckRecord[Field.deletedAt] as? Date {
            self = .tombstone(Tombstone(workID: workID, deletedAt: deletedAt))
            return
        }
        let payload = try (ckRecord[Field.payload] as? CKAsset)?.fileURL.map { try Data(contentsOf: $0) }
        self = .record(WorkRecord(workID: workID, schemaVersion: ckRecord[Field.schemaVersion] as? Int ?? 0,
                                  updatedAt: ckRecord[Field.updatedAt] as? Date ?? .distantPast, payload: payload ?? Data()))
    }

    /// Sets the CloudKit record's fields to this entry, writing the payload into `assetDirectory` for upload.
    func write(to ckRecord: CKRecord, assetDirectory: URL) throws {
        switch self {
        case .record(let record):
            try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
            let file = assetDirectory.appending(path: "\(UUID().uuidString).json")
            try record.payload.write(to: file)
            ckRecord[Field.schemaVersion] = record.schemaVersion
            ckRecord[Field.updatedAt] = record.updatedAt
            ckRecord[Field.payload] = CKAsset(fileURL: file)
            ckRecord[Field.deletedAt] = nil
        case .tombstone(let tombstone):
            for field in [Field.schemaVersion, Field.updatedAt, Field.payload] { ckRecord[field] = nil }
            ckRecord[Field.deletedAt] = tombstone.deletedAt
        }
    }

    /// The CloudKit record's field names.
    enum Field {
        static let schemaVersion = "schemaVersion", updatedAt = "updatedAt", payload = "payload", deletedAt = "deletedAt"
    }

    /// A fetched record whose name is not a Work ID; sync skips it.
    struct BadRecordName: Error, Equatable { let name: String }
}

extension RemoteEntry {
    /// Whether this device's entry goes over `server`, the one CloudKit holds for the same Work: the same
    /// whole-Work last-writer-wins every device applies on fetch, so every device ends with the same winner.
    func replaces(_ server: RemoteEntry) -> Bool {
        switch (self, server) {
        case (.record(let mine), .record(let theirs)):
            if mine.updatedAt != theirs.updatedAt { return mine.updatedAt > theirs.updatedAt }
            return theirs.payload.lexicographicallyPrecedes(mine.payload)
        case (.record(let mine), .tombstone(let theirs)):
            return mine.updatedAt > theirs.deletedAt
        case (.tombstone(let mine), .record(let theirs)):
            return mine.deletedAt >= theirs.updatedAt
        case (.tombstone(let mine), .tombstone(let theirs)):
            return mine.deletedAt > theirs.deletedAt
        }
    }
}
