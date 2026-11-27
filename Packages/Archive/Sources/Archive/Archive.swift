import Foundation

public enum CompressionMethod: Sendable, Hashable {
    case stored
    case deflated
}

/// Sizes are what reading the entry produced and consumed, never the sizes its headers declare.
public struct ArchiveEntry: Sendable, Hashable {
    /// The path inside the archive: relative, UTF-8, in Unicode Normalization Form C.
    public let path: String
    public let method: CompressionMethod
    public let compressedSize: Int64
    public let uncompressedSize: Int64
}

public struct ArchiveItem: Sendable, Hashable {
    public var path: String
    public var contents: Data
    public var method: CompressionMethod

    public init(path: String, contents: Data, method: CompressionMethod) {
        self.path = path
        self.contents = contents
        self.method = method
    }
}

/// Caps that keep a hostile archive from exhausting memory or time (`specs/R1/library-import.md`, Safety).
public struct ArchiveLimits: Sendable, Hashable {
    /// Directories count as entries.
    public var maxEntryCount: Int
    public var maxTotalUncompressedSize: Int64
    /// The most an entry may expand per compressed byte. It is checked only once the entry has expanded past
    /// 1 MiB, so small, highly repetitive files still open while a zip bomb is stopped early.
    public var maxCompressionRatio: Int64

    public init(maxEntryCount: Int = 5_000, maxTotalUncompressedSize: Int64 = 4 << 30, maxCompressionRatio: Int64 = 100) {
        self.maxEntryCount = maxEntryCount
        self.maxTotalUncompressedSize = maxTotalUncompressedSize
        self.maxCompressionRatio = maxCompressionRatio
    }
}

public enum ArchiveError: Error, Equatable, Sendable {
    /// The file is not a ZIP archive, or it is truncated or damaged. The message is for logs, not for branching.
    case corrupt(String)
    /// An entry's path is empty, absolute, has an empty or `..` component, or is not UTF-8.
    case unsafePath(String)
    /// Two entries have the same path once normalized.
    case duplicatePath(String)
    /// An entry is encrypted, is a link or device, or is compressed with a method other than stored or deflated.
    case unsupportedEntry(String)
    case tooManyEntries(limit: Int)
    case totalSizeExceeded(limit: Int64)
    case compressionRatioExceeded(path: String, limit: Int64)
    case entryNotFound(String)
    /// The archive could not be written. The message is for logs, not for branching.
    case writeFailed(String)
}

/// The entry name in Normalization Form C, or nil when it is empty, absolute, or has an empty or `..` component.
/// libarchive returns NFD for names flagged UTF-8 and raw bytes for the rest, so normalizing keeps a path from
/// depending on how the archive was written. Backslashes count as separators because Windows tools treat them so.
func archivePath(_ name: String) -> String? {
    let path = name.precomposedStringWithCanonicalMapping
    guard !path.isEmpty, !path.contains(Character("\0")), path.prefixMatch(of: /[A-Za-z]:/) == nil else { return nil }
    let components = path.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || $0 == "\\" })
    guard components.allSatisfy({ !$0.isEmpty && $0 != ".." }) else { return nil }
    return path
}
