# R1 · Persistence & Sync

_Package: `Persistence` · Tier 1 · Depends on: Comic Structure_

## Purpose
Store the Library on the device and sync everything through the user's iCloud: model data, imported Sources, Page images, Cast reference crops and Renders.

## Requirements
1. **Model data** (Works, Chapters, Pages, Panels, Bubbles, Lines, Cast, Render records) is stored locally and synced via the user's **private** iCloud (CloudKit). Suggested implementation: SwiftData with CloudKit sync, or Core Data + `NSPersistentCloudKitContainer`; the Lead approves the choice in M1.
2. **Files** (Sources, Page images, reference crops, Render videos) live in the app's iCloud Drive container and are downloaded on demand. Only references are stored in the model.
3. **Sync scope is everything**, including Sources and Renders (decision Q18/Q28). A Work synced to another device must be fully usable after its files download.
4. **Local eviction:** the local copy of any file that is safely in iCloud can be evicted to save space and is re-downloaded when needed. Renders are evicted first (oldest viewed first). Default local Render budget 2 GB, user-adjustable; "Clear downloaded Renders" frees local copies only.
5. **iCloud unavailable or full:** keep everything locally, show a non-blocking warning, retry periodically. Never lose local data.
6. **Conflicts:** last writer wins per entity, using `updatedAt`. Edit operations are small, so whole-entity conflicts are rare; a conflict on a Line keeps both texts in the edit history so the user can restore.
7. **Schema versioning:** every stored model carries `schemaVersion`; migrations are tested.
8. **Privacy:** nothing in this module talks to our backend. All data stays on device and in the user's iCloud.

## Public interface (sketch)
```swift
public protocol LibraryStore {
  func works(kind: WorkKind?) async throws -> [Work]
  func save(_ work: Work) async throws
  func delete(_ workID: Work.ID) async throws          // deletes model + files, everywhere
  func fileURL(for ref: FileRef) async throws -> URL   // downloads if needed
  func store(file: URL, kind: FileKind) async throws -> FileRef
  func evictLocalCopy(_ ref: FileRef) async throws
  var syncStatus: AsyncStream<SyncStatus> { get }      // .synced, .syncing, .offline, .iCloudFull, .error
}
```

## Acceptance tests
- Create a Work on device A; it appears on device B with all Pages viewable after download (manual test on two physical devices, plus a fake-CloudKit integration test).
- Evicting a Render's local copy and opening it re-downloads and plays it.
- With iCloud signed out, all features work locally and the warning shows; signing in later uploads everything.
- Migration tests for each schema version.
- Deleting a Work removes its files from iCloud Drive and its records from CloudKit.

## Out of scope
Import parsing (Library & Import), backend communication.
