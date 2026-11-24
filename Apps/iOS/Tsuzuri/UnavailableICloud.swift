#if DEBUG
import ComicStructure
import Foundation
import Persistence

/// iCloud as a signed-out device sees it: every request fails with `ICloudError.accountUnavailable`, so a
/// `CloudLibraryStore` works locally and reports `.offline`. UI test launches use it so they never reach iCloud.
struct UnavailableICloud: RecordSyncBackend, UbiquitousFileContainer {
    func fetchChanges(since token: ChangeToken?) async throws -> RecordChanges { throw ICloudError.accountUnavailable }
    func save(_ records: [WorkRecord]) async throws { throw ICloudError.accountUnavailable }
    func delete(_ tombstones: [Tombstone]) async throws { throw ICloudError.accountUnavailable }
    func copyIn(_ local: URL, as ref: FileRef) async throws { throw ICloudError.accountUnavailable }
    func download(_ ref: FileRef, to local: URL) async throws { throw ICloudError.accountUnavailable }
    func isUploaded(_ ref: FileRef) async throws -> Bool { throw ICloudError.accountUnavailable }
    func remove(_ ref: FileRef) async throws { throw ICloudError.accountUnavailable }
}
#endif
