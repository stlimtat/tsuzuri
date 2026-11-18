import Persistence
import SwiftUI

@main
struct TsuzuriApp: App {
    /// The Library on this device; ticket #10 replaces it with `CloudLibraryStore`.
    private let model: DebugLibraryModel? = {
        let root = URL.applicationSupportDirectory.appending(path: "Library", directoryHint: .isDirectory)
        return (try? LocalLibraryStore(root: root)).map { DebugLibraryModel(store: $0) }
    }()

    var body: some Scene {
        WindowGroup {
            if let model {
                DebugLibraryView(model: model)
            } else {
                ContentUnavailableView("The Library could not be opened.", systemImage: "exclamationmark.triangle")
            }
        }
    }
}
