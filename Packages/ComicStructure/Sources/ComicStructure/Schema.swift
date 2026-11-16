import Foundation

/// The versioned JSON form of a Work: `{"schemaVersion": n, "work": {...}}`.
/// On any breaking model change: bump `currentVersion`, migrate older payloads in `decode`, and add a migration test.
public enum ComicSchema {
    public static let currentVersion = 1

    public enum Error: Swift.Error, Equatable {
        case unsupportedVersion(Int)
    }

    public static func encode(_ work: Work) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Document(schemaVersion: currentVersion, work: work))
    }

    /// Decodes and validates the invariants (stored and synced files are untrusted input).
    public static func decode(_ data: Data) throws -> Work {
        struct Header: Decodable { let schemaVersion: Int }
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        // ponytail: v1 is the only version; add migrations here with the first bump.
        guard version == currentVersion else { throw Error.unsupportedVersion(version) }
        let work = try JSONDecoder().decode(Document.self, from: data).work
        try Invariants.validate(work)
        return work
    }

    private struct Document: Codable {
        let schemaVersion: Int
        let work: Work
    }
}
