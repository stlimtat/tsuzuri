import Foundation

/// Which Library the app opens on this launch.
enum LibraryLaunch: Equatable, Sendable {
    /// The user's Library in Application Support, synced through their iCloud.
    case live
    /// A UI test run: the Library at `root`, which never touches iCloud and so always reports `.offline`.
    case uiTesting(root: URL)

    /// The launch argument a UI test passes to get `.uiTesting`.
    static let uiTestingArgument = "-TsuzuriUITesting"
    /// The launch environment key naming the UI test Library's directory under the app's temporary directory, so
    /// a relaunch can reopen the same one. A name, not a path: the test runner can't see the app's container.
    static let libraryDirectoryKey = "TSUZURI_UI_TEST_LIBRARY"

    /// `.live` unless `arguments` holds `uiTestingArgument`. The UI test Library is the directory under
    /// `temporaryDirectory` named by `libraryDirectoryKey` in `environment` when that is set and not empty,
    /// otherwise a new one named by `newName`, so every launch starts with an empty Library.
    /// ponytail: nothing removes these directories; the system purges the app's temporary directory.
    init(arguments: [String], environment: [String: String], temporaryDirectory: URL,
         newName: () -> String = { "TsuzuriUITesting-\(UUID().uuidString)" }) {
        guard arguments.contains(Self.uiTestingArgument) else {
            self = .live
            return
        }
        let name = environment[Self.libraryDirectoryKey].flatMap { $0.isEmpty ? nil : $0 } ?? newName()
        self = .uiTesting(root: temporaryDirectory.appending(path: name, directoryHint: .isDirectory))
    }
}
