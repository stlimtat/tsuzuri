import CloudKit
import Foundation

/// The user's private CloudKit database: one custom zone holding one `Work` record per Work (`RemoteEntry`),
/// read through the zone's change feed.
///
/// Saves are conditional (`.ifServerRecordUnchanged`): when another device saved the record since, the
/// server's copy comes back and whole-Work last-writer-wins (`RemoteEntry.replaces`) decides whether this save
/// goes over it, so a stale save from a third device can't replace a newer record.
public actor CloudKitRecordBackend: RecordSyncBackend {
    private let configuration: LiveICloudConfiguration
    private var database: CKDatabase?
    /// Whether this process has made sure the zone exists.
    private var zoneReady = false
    /// Where payloads are written for CloudKit to upload as assets; each write cleans up after itself.
    private let assetRoot = FileManager.default.temporaryDirectory.appending(path: "CloudKitAssets", directoryHint: .isDirectory)
    /// CloudKit's limit is 400 records per request.
    private static let batchSize = 200
    /// Conflict rounds per save before giving up until the next sync.
    private static let conflictAttempts = 3

    public init(configuration: LiveICloudConfiguration) { self.configuration = configuration }

    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: configuration.zoneName, ownerName: CKCurrentUserDefaultName) }

    /// The database, created on first use. CloudKit stops the process when an app without the iCloud
    /// entitlement creates a container, so it is created only once iCloud is signed in for this app
    /// (`ubiquityIdentityToken` is nil when signed out, with iCloud Drive off for the app, and in unsigned builds).
    private func openDatabase() throws -> CKDatabase {
        if let database { return database }
        guard FileManager.default.ubiquityIdentityToken != nil else { throw ICloudError.accountUnavailable }
        let database = CKContainer(identifier: configuration.containerIdentifier).database(with: configuration.databaseScope)
        self.database = database
        return database
    }

    private func ensureZone(in database: CKDatabase) async throws {
        guard !zoneReady else { return }
        let (saved, _) = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        for result in saved.values { _ = try result.get() }
        zoneReady = true
    }

    /// Runs `request` against the zone, creating the zone first if needed and once more if it has gone, and
    /// turning errors sync understands into `ICloudError`.
    private func perform<T>(_ request: (CKDatabase) async throws -> T) async throws -> T {
        var recreated = false
        while true {
            let database = try openDatabase()
            do {
                try await ensureZone(in: database)
                return try await request(database)
            } catch {
                switch CloudKitRecovery(error) {
                case .fail(let reason): throw reason
                case .recreateZone where !recreated:
                    zoneReady = false
                    recreated = true
                default: throw error
                }
            }
        }
    }

    public func fetchChanges(since token: ChangeToken?) async throws -> RecordChanges {
        try await perform { database in
            var serverToken = token.flatMap(Self.serverToken)
            var latest: [UUID: RemoteEntry] = [:]
            while true {
                let page: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                           deletions: [CKDatabase.RecordZoneChange.Deletion], changeToken: CKServerChangeToken, moreComing: Bool)
                do {
                    page = try await database.recordZoneChanges(inZoneWith: zoneID, since: serverToken)
                } catch where serverToken != nil && [.refetchFromStart, .recreateZone].contains(CloudKitRecovery(error)) {
                    // Too old, or from before the zone was recreated: read everything again.
                    serverToken = nil
                    latest = [:]
                    continue
                }
                for result in page.modificationResultsByID.values {
                    // A record CloudKit couldn't return, or one not named by a Work ID, is left out.
                    guard case .success(let modification) = result, let entry = try? RemoteEntry(modification.record) else { continue }
                    latest[entry.workID] = entry
                }
                serverToken = page.changeToken
                if !page.moreComing { break }
            }
            var changed: [WorkRecord] = [], deleted: [Tombstone] = []
            for entry in latest.values {
                switch entry {
                case .record(let record): changed.append(record)
                case .tombstone(let tombstone): deleted.append(tombstone)
                }
            }
            return RecordChanges(changed: changed, deleted: deleted, token: try Self.changeToken(serverToken))
        }
    }

    public func save(_ records: [WorkRecord]) async throws { try await write(records.map(RemoteEntry.record)) }

    public func delete(_ tombstones: [Tombstone]) async throws { try await write(tombstones.map(RemoteEntry.tombstone)) }

    private func write(_ entries: [RemoteEntry]) async throws {
        guard !entries.isEmpty else { return }
        let assets = assetRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: assets) }
        for start in stride(from: 0, to: entries.count, by: Self.batchSize) {
            let batch = entries[start..<min(start + Self.batchSize, entries.count)]
            try await perform { database in try await write(batch, to: database, assets: assets) }
        }
    }

    /// Saves each entry unless the server's record is newer; retries the ones that lost a race with another
    /// device's save and still win.
    private func write(_ entries: ArraySlice<RemoteEntry>, to database: CKDatabase, assets: URL) async throws {
        var pending: [CKRecord.ID: (entry: RemoteEntry, record: CKRecord)] = [:]
        for entry in entries {
            let record = CKRecord(recordType: RemoteEntry.recordType,
                                  recordID: CKRecord.ID(recordName: entry.workID.uuidString, zoneID: zoneID))
            try entry.write(to: record, assetDirectory: assets)
            pending[record.recordID] = (entry, record)
        }
        for _ in 0..<Self.conflictAttempts where !pending.isEmpty {
            let (saved, _) = try await database.modifyRecords(saving: pending.values.map(\.record), deleting: [],
                                                              savePolicy: .ifServerRecordUnchanged, atomically: false)
            var retry: [CKRecord.ID: (entry: RemoteEntry, record: CKRecord)] = [:]
            for (id, result) in saved {
                guard case .failure(let error) = result else { continue }
                guard CloudKitRecovery(error) == .resolveConflict, let server = (error as? CKError)?.serverRecord,
                      let entry = pending[id]?.entry
                else { throw error }
                // The server's record is newer: leave it; the next fetch brings it to this device.
                if let theirs = try? RemoteEntry(server), !entry.replaces(theirs) { continue }
                try entry.write(to: server, assetDirectory: assets)
                retry[id] = (entry, server)
            }
            pending = retry
        }
        // Still racing other devices: reported as an error, and everything stays queued for the next sync.
        if !pending.isEmpty { throw CKError(.serverRecordChanged) }
    }

    private static func serverToken(_ token: ChangeToken) -> CKServerChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: token.rawValue)
    }

    private static func changeToken(_ token: CKServerChangeToken?) throws -> ChangeToken {
        guard let token else { return ChangeToken(rawValue: Data()) }
        return ChangeToken(rawValue: try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true))
    }
}
