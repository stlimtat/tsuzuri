import Foundation
import Persistence

/// The non-blocking banner the debug screen shows while iCloud can't take changes.
enum SyncBanner: Equatable, Sendable {
    case offline, iCloudFull

    init?(_ status: SyncStatus) {
        switch status {
        case .offline: self = .offline
        case .iCloudFull: self = .iCloudFull
        default: return nil
        }
    }
}

/// The debug screen's one-line sync status.
enum SyncStatusLine {
    static func text(for status: SyncStatus) -> String {
        switch status {
        case .synced: String(localized: "Synced", comment: "Sync status: everything is in iCloud.")
        case .syncing: String(localized: "Syncing", comment: "Sync status: changes are waiting to reach iCloud.")
        case .offline: String(localized: "Offline", comment: "Sync status: iCloud is unavailable.")
        case .iCloudFull: String(localized: "iCloud full", comment: "Sync status: the user's iCloud storage is full.")
        case .error(let message): String(localized: "Error: \(message)", comment: "Sync status: sync failed, with the reason.")
        }
    }
}
