import CloudKit
import Foundation
import Testing
@testable import Persistence

/// The live iCloud backends' pure parts, checked without creating a `CKContainer` (no entitlement needed).
@Suite struct LiveICloudConfigurationTests {
    @Test func namesTheAppsOwnContainerAndThePrivateDatabase() {
        let configuration = LiveICloudConfiguration.make(bundleIdentifier: "net.stlim.tsuzuri")

        #expect(configuration.containerIdentifier == "iCloud.net.stlim.tsuzuri")
        #expect(configuration.databaseScope == .private)
        #expect(configuration.zoneName == "Library")
    }
}

@Suite struct CloudKitErrorTests {
    /// Signed out, no network or CloudKit busy: sync shows offline, keeps everything queued and retries.
    @Test(arguments: [CKError.Code.notAuthenticated, .networkUnavailable, .networkFailure, .serviceUnavailable,
                      .requestRateLimited, .zoneBusy, .accountTemporarilyUnavailable])
    func unreachableICloudIsAccountUnavailable(code: CKError.Code) {
        #expect(CloudKitRecovery(CKError(code)) == .fail(.accountUnavailable))
    }

    @Test func fullICloudIsQuotaExceeded() {
        #expect(CloudKitRecovery(CKError(.quotaExceeded)) == .fail(.quotaExceeded))
    }

    /// `userDeletedZone`: the user deleted the app's iCloud data in Settings.
    @Test(arguments: [CKError.Code.zoneNotFound, .userDeletedZone])
    func aMissingZoneIsRecreated(code: CKError.Code) {
        #expect(CloudKitRecovery(CKError(code)) == .recreateZone)
    }

    @Test func anExpiredChangeTokenRefetchesFromTheStart() {
        #expect(CloudKitRecovery(CKError(.changeTokenExpired)) == .refetchFromStart)
    }

    @Test func aChangedServerRecordIsAConflictToResolve() {
        #expect(CloudKitRecovery(CKError(.serverRecordChanged)) == .resolveConflict)
    }

    /// A batch fails as a whole with `partialFailure`; the record that caused it says why, the rest only say
    /// they were part of the failed batch.
    @Test func aPartialFailureIsJudgedByTheRecordThatCausedIt() {
        let zone = CKRecordZone.ID(zoneName: "Library")
        let error = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [
            CKRecord.ID(recordName: "a", zoneID: zone): CKError(.batchRequestFailed),
            CKRecord.ID(recordName: "b", zoneID: zone): CKError(.quotaExceeded),
        ]])

        #expect(CloudKitRecovery(error) == .fail(.quotaExceeded))
    }

    @Test func anythingElseIsPassedOn() {
        #expect(CloudKitRecovery(CKError(.permissionFailure)) == .passOn)
        #expect(CloudKitRecovery(CocoaError(.fileNoSuchFile)) == .passOn)
    }
}

/// How a Work's record or tombstone is laid out in a CloudKit record, read back the way a fetch reads it.
@Suite struct CloudKitRecordTests {
    let zone = CKRecordZone.ID(zoneName: "Library")
    let assets = FileManager.default.temporaryDirectory.appending(path: "CloudKitRecordTests-\(UUID())")

    func blankRecord(for id: UUID) -> CKRecord {
        CKRecord(recordType: RemoteEntry.recordType, recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zone))
    }

    @Test func aWorkRecordReadsBackAsWritten() throws {
        let record = WorkRecord(workID: UUID(), schemaVersion: 3, updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                payload: Data(#"{"a":1}"#.utf8))
        let ckRecord = blankRecord(for: record.workID)

        try RemoteEntry.record(record).write(to: ckRecord, assetDirectory: assets)

        #expect(try RemoteEntry(ckRecord) == .record(record))
    }

    /// Deleting writes the tombstone over the Work's record, so no payload is left behind.
    @Test func aTombstoneWrittenOverAWorkRecordReadsBackAsTheTombstone() throws {
        let id = UUID()
        let ckRecord = blankRecord(for: id)
        try RemoteEntry.record(WorkRecord(workID: id, schemaVersion: 1, updatedAt: Date(), payload: Data("{}".utf8)))
            .write(to: ckRecord, assetDirectory: assets)
        let tombstone = Tombstone(workID: id, deletedAt: Date(timeIntervalSince1970: 1_800_000_000))

        try RemoteEntry.tombstone(tombstone).write(to: ckRecord, assetDirectory: assets)

        #expect(try RemoteEntry(ckRecord) == .tombstone(tombstone))
        #expect(ckRecord[RemoteEntry.Field.payload] == nil)
    }

    /// A save later than the delete brings the Work back over its tombstone.
    @Test func aWorkRecordWrittenOverATombstoneReadsBackAsTheRecord() throws {
        let id = UUID()
        let ckRecord = blankRecord(for: id)
        try RemoteEntry.tombstone(Tombstone(workID: id, deletedAt: Date(timeIntervalSince1970: 1_700_000_000)))
            .write(to: ckRecord, assetDirectory: assets)
        let record = WorkRecord(workID: id, schemaVersion: 1, updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                payload: Data("{}".utf8))

        try RemoteEntry.record(record).write(to: ckRecord, assetDirectory: assets)

        #expect(try RemoteEntry(ckRecord) == .record(record))
    }

    /// A record with no payload (tampered, or half-written by an older build) still reaches sync, whose
    /// `verified()` rejects the empty payload and reports it.
    @Test func aRecordWithoutFieldsReadsBackWithAnEmptyPayload() throws {
        let id = UUID()

        let entry = try RemoteEntry(blankRecord(for: id))

        #expect(entry == .record(WorkRecord(workID: id, schemaVersion: 0, updatedAt: .distantPast, payload: Data())))
    }

    @Test func aRecordNotNamedByAWorkIDIsRefused() {
        let ckRecord = CKRecord(recordType: RemoteEntry.recordType, recordID: CKRecord.ID(recordName: "../etc", zoneID: zone))

        #expect(throws: RemoteEntry.BadRecordName(name: "../etc")) { try RemoteEntry(ckRecord) }
    }
}

/// When CloudKit refuses a save because the record changed since this device read it (a third device saved
/// in between), whole-Work last-writer-wins (ADR 0007) decides whether this device's save goes over it.
@Suite struct ConflictResolutionTests {
    let id = UUID()
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func record(_ at: Date, _ payload: String = "{}") -> RemoteEntry {
        .record(WorkRecord(workID: id, schemaVersion: 1, updatedAt: at, payload: Data(payload.utf8)))
    }
    func tombstone(_ at: Date) -> RemoteEntry { .tombstone(Tombstone(workID: id, deletedAt: at)) }

    @Test func theLaterSaveReplacesTheServerRecordAndTheEarlierDoesNot() {
        #expect(record(t0 + 10).replaces(record(t0)))
        #expect(!record(t0).replaces(record(t0 + 10)))
    }

    /// The tie-break `WorkRecord.supersedes` uses on fetch: the greater payload bytes.
    @Test func onATieTheGreaterPayloadReplacesTheServerRecord() {
        #expect(record(t0, "{b}").replaces(record(t0, "{a}")))
        #expect(!record(t0, "{a}").replaces(record(t0, "{b}")))
        #expect(!record(t0, "{a}").replaces(record(t0, "{a}")))
    }

    /// Matches the store's rule: a save no later than the delete is dropped.
    @Test func aSaveReplacesATombstoneOnlyIfLaterThanTheDelete() {
        #expect(record(t0 + 1).replaces(tombstone(t0)))
        #expect(!record(t0).replaces(tombstone(t0)))
    }

    /// A tombstone covers every save at or before the delete.
    @Test func aTombstoneReplacesASaveNoLaterThanTheDelete() {
        #expect(tombstone(t0).replaces(record(t0)))
        #expect(!tombstone(t0).replaces(record(t0 + 1)))
    }

    /// Two deletes: the later one stays, so the tombstone covers the most saves.
    @Test func theLaterTombstoneReplacesTheEarlier() {
        #expect(tombstone(t0 + 1).replaces(tombstone(t0)))
        #expect(!tombstone(t0).replaces(tombstone(t0)))
    }
}
