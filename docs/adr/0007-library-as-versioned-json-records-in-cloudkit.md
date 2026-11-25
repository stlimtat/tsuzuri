# The Library is one versioned JSON record per Work, synced through CloudKit

The Library stays as one versioned JSON record per Work (`ComicSchema`), kept local-first and synced through the CloudKit private database, with Page files in iCloud Drive. We rejected SwiftData and `NSPersistentCloudKitContainer`. The model is made of value types with pure edit operations and has its own versioned schema. A second persistence model would duplicate the Lead-owned types (ADR 0002) and put the sync framework's schema rules in charge of ours.

## Consequences
- **Conflicts in M1 are whole-Work last-writer-wins by `Work.updatedAt`.** This is a deliberate stand-in for the per-entity rule in `specs/R1/persistence-sync.md` requirement 6, acceptable only while no Work is edited on two devices.
- **Deletes are tombstoned.** Deleting a Work writes a tombstone record (Work ID, `deletedAt`). Any save of that Work, local or remote, whose `updatedAt` is not later than `deletedAt` is dropped, so a save queued on an offline device can't bring a deleted Work back.
- **Per-entity merge must land before multi-device editing (M2).** Under whole-Work last-writer-wins, edits made on two devices would silently lose one side.
- Schema changes go through `ComicSchema` versioning, and the CloudKit record schema must be deployed to production before a TestFlight build ships.
