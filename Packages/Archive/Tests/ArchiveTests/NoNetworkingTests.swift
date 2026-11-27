import Foundation
import Testing

/// ADR 0004 (on-device first): reading and writing archives never touches the network, in our Swift or in the
/// vendored libarchive C sources.
@Suite struct NoNetworkingTests {
    static let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources")

    static var swiftNetworking: Regex<Substring> { /URLSession|URLRequest|import\s+Network|NWConnection|NWPathMonitor|CFNetwork|CFStream|Socket|https?:\/\// }
    static var cNetworking: Regex<Substring> { /\bsocket\s*\(|\bconnect\s*\(|\bgetaddrinfo\b|\bgethostbyname|<sys\/socket\.h>|<netinet\/|<netdb\.h>/ }

    @Test func archiveSourcesUseNoNetworking() throws {
        let files = try #require(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
        let swift = files.filter { $0.pathExtension == "swift" }
        let c = files.filter { ["c", "h"].contains($0.pathExtension) }
        #expect(!swift.isEmpty && !c.isEmpty)
        for (file, pattern) in swift.map({ ($0, Self.swiftNetworking) }) + c.map({ ($0, Self.cNetworking) }) {
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") where line.contains(pattern) {
                Issue.record("\(file.lastPathComponent) reaches the network: \(line)")
            }
        }
    }
}
