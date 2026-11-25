import Persistence
import Testing

/// What the debug screen shows for each `SyncStatus`: a status line always, a banner only when iCloud can't
/// take changes (they stay on this device, and nothing is blocked).
@Suite struct SyncStatusDisplayTests {
    @Test func offlineAndICloudFullShowABanner() {
        #expect(SyncBanner(.offline) == .offline)
        #expect(SyncBanner(.iCloudFull) == .iCloudFull)
    }

    @Test(arguments: [SyncStatus.synced, .syncing, .error("Skipped 1 bad record(s)")])
    func otherStatusesShowNoBanner(status: SyncStatus) {
        #expect(SyncBanner(status) == nil)
    }

    @Test func theStatusLineNamesEachStatusAndAnErrorsMessage() {
        #expect(SyncStatusLine.text(for: .synced) == "Synced")
        #expect(SyncStatusLine.text(for: .syncing) == "Syncing")
        #expect(SyncStatusLine.text(for: .offline) == "Offline")
        #expect(SyncStatusLine.text(for: .iCloudFull) == "iCloud full")
        #expect(SyncStatusLine.text(for: .error("schema not deployed")) == "Error: schema not deployed")
    }
}
