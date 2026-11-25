import Foundation
import Testing

/// specs/R1/persistence-sync.md requirement 8: Persistence talks only to the user's iCloud (CloudKit and
/// iCloud Drive), never to a server of ours or anyone else's.
@Suite struct NoNetworkingTests {
    static let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources")

    /// APIs that reach the network other than through CloudKit or iCloud Drive.
    static var networking: Regex<Substring> { /URLSession|URLRequest|import\s+Network|NWConnection|NWPathMonitor|CFNetwork|CFStream|Socket|https?:\/\// }

    @Test func persistenceSourcesUseNoNetworkingBeyondICloud() throws {
        let files = try #require(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") where line.contains(Self.networking) {
                Issue.record("\(file.lastPathComponent) reaches the network outside iCloud: \(line)")
            }
        }
    }
}
