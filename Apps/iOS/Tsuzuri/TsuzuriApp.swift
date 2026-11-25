import CloudKit
import Persistence
import SwiftUI

@main
struct TsuzuriApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let library = SyncedLibrary.open()

    var body: some Scene {
        WindowGroup {
            if let library {
                DebugLibraryView(model: library.model)
            } else {
                ContentUnavailableView("The Library could not be opened.", systemImage: "exclamationmark.triangle")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library?.becameActive() }
        }
    }
}

/// The Library on this device, synced through the user's iCloud for the app's lifetime. With iCloud
/// unavailable (signed out, or an unsigned build) it works locally and reports `.offline`.
///
/// A UI test launch (`LibraryLaunch.uiTesting`, Debug builds only) opens its own Library with iCloud unavailable.
///
/// No push: remote changes arrive when the app becomes active (and on pull to refresh), not while it is open.
@MainActor
final class SyncedLibrary {
    let model: DebugLibraryModel
    private let store: CloudLibraryStore
    private var tasks: [Task<Void, Never>] = []

    static func open() -> SyncedLibrary? {
        #if DEBUG
        let process = ProcessInfo.processInfo
        if case .uiTesting(let root) = LibraryLaunch(arguments: process.arguments, environment: process.environment,
                                                     temporaryDirectory: .temporaryDirectory) {
            guard let store = try? CloudLibraryStore(root: root, records: UnavailableICloud(), files: UnavailableICloud())
            else { return nil }
            return SyncedLibrary(store: store)
        }
        #endif
        let configuration = LiveICloudConfiguration.make(bundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        let root = URL.applicationSupportDirectory.appending(path: "Library", directoryHint: .isDirectory)
        guard let store = try? CloudLibraryStore(
            root: root,
            records: CloudKitRecordBackend(configuration: configuration),
            files: ICloudDriveFileContainer(containerIdentifier: configuration.containerIdentifier))
        else { return nil }
        return SyncedLibrary(store: store)
    }

    private init(store: CloudLibraryStore) {
        self.store = store
        model = DebugLibraryModel(store: store, sync: { try await store.sync() })
        tasks = [
            Task { await store.keepSynced() },
            Task { [model] in await model.followSyncStatus() },
            Task { await Self.requestSync(of: store, on: .NSUbiquityIdentityDidChange) },
            Task { await Self.requestSync(of: store, on: .CKAccountChanged) },
        ]
    }

    /// Syncs on every `notification` (an iCloud account change) until cancelled.
    private static func requestSync(of store: CloudLibraryStore, on notification: Notification.Name) async {
        for await _ in NotificationCenter.default.notifications(named: notification).map({ _ in () }) {
            await store.requestSync()
        }
    }

    /// On launch and on every return to the foreground: wake `keepSynced`, then refresh the list so Works made
    /// on another device show up.
    func becameActive() {
        Task { [store, model] in
            await store.requestSync()
            try? await model.refresh()
        }
    }

    deinit { for task in tasks { task.cancel() } }
}
