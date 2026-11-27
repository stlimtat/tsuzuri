internal import CArchive
import Foundation

/// Opening reads every entry once, so a damaged archive, an unsafe path or a zip bomb fails at open rather than
/// halfway through a later read. Reads check the limits again in case the file has changed since.
public struct ArchiveReader: Sendable {
    /// In archive order, without directories.
    public let entries: [ArchiveEntry]
    private let url: URL
    private let limits: ArchiveLimits

    public init(contentsOf url: URL, limits: ArchiveLimits = ArchiveLimits()) throws(ArchiveError) {
        let handle = try ReadHandle(url: url, limits: limits)
        var entries: [ArchiveEntry] = []
        var paths = Set<String>()
        var total: Int64 = 0
        while let file = try handle.nextFile() {
            guard paths.insert(file.path).inserted else { throw .duplicatePath(file.path) }
            let read = try handle.readData(of: file, budget: limits.maxTotalUncompressedSize - total, keepingBytes: false)
            total += read.uncompressedSize
            entries.append(ArchiveEntry(
                path: file.path, method: file.method,
                compressedSize: read.compressedSize, uncompressedSize: read.uncompressedSize))
        }
        self.entries = entries
        self.url = url
        self.limits = limits
    }

    public func data(for path: String) throws(ArchiveError) -> Data {
        guard entries.contains(where: { $0.path == path }) else { throw .entryNotFound(path) }
        let handle = try ReadHandle(url: url, limits: limits)
        while let file = try handle.nextFile() {
            if file.path == path {
                return try handle.readData(of: file, budget: limits.maxTotalUncompressedSize, keepingBytes: true).bytes
            }
        }
        throw .entryNotFound(path)
    }
}

/// An open libarchive reader that walks a ZIP's entries in archive order, enforcing the limits as it goes.
private final class ReadHandle {
    struct File {
        let path: String
        let method: CompressionMethod
    }

    /// An entry's compression ratio is checked only past this many output bytes (see `ArchiveLimits`).
    static let ratioGrace: Int64 = 1 << 20

    private let archive: OpaquePointer
    private let limits: ArchiveLimits
    private var headerCount = 0

    init(url: URL, limits: ArchiveLimits) throws(ArchiveError) {
        guard let archive = archive_read_new() else { throw .corrupt("libarchive could not allocate a reader") }
        self.archive = archive
        self.limits = limits
        // Only the seekable reader: it trusts the central directory, as other ZIP tools do, rather than local
        // headers that a crafted archive can make disagree with it.
        archive_read_support_format_zip_seekable(archive)
        let status = url.withUnsafeFileSystemRepresentation { archive_read_open_filename(archive, $0, 64 * 1024) }
        guard status == ARCHIVE_OK else { throw .corrupt(errorMessage) }
    }

    deinit { archive_read_free(archive) }

    /// The next regular file, skipping directories, or nil at the end of the archive.
    func nextFile() throws(ArchiveError) -> File? {
        while true {
            var entry: OpaquePointer?
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { return nil }
            // A warning here means the local header disagrees with the central directory: treat it as damage.
            guard status == ARCHIVE_OK, let entry else { throw .corrupt(errorMessage) }
            headerCount += 1
            guard headerCount <= limits.maxEntryCount else { throw .tooManyEntries(limit: limits.maxEntryCount) }

            let type = archive_entry_filetype(entry) & 0o170000
            if type == 0o040000 { continue }
            let name = archive_entry_pathname(entry).map { String(validatingCString: $0) } ?? nil
            guard let name, let path = archivePath(name) else {
                throw .unsafePath(archive_entry_pathname(entry).map { String(cString: $0) } ?? "")
            }
            guard type == 0o100000, archive_entry_is_encrypted(entry) == 0, let method else {
                throw .unsupportedEntry(path)
            }
            return File(path: path, method: method)
        }
    }

    /// Reads the current entry's data, failing once it expands past `budget` bytes or past the compression-ratio
    /// limit. Sizes are counted from the bytes actually produced and consumed. Bytes are kept only when asked.
    func readData(of file: File, budget: Int64, keepingBytes: Bool) throws(ArchiveError)
        -> (bytes: Data, compressedSize: Int64, uncompressedSize: Int64) {
        let start = archive_filter_bytes(archive, 0)
        var bytes = Data()
        var produced: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { archive_read_data(archive, $0.baseAddress, $0.count) }
            if count == 0 { break }
            guard count > 0 else { throw .corrupt(errorMessage) }
            produced += Int64(count)
            guard produced <= budget else { throw .totalSizeExceeded(limit: limits.maxTotalUncompressedSize) }
            let consumed = archive_filter_bytes(archive, 0) - start
            let (allowed, overflow) = consumed.multipliedReportingOverflow(by: limits.maxCompressionRatio)
            if produced > Self.ratioGrace, !overflow, produced > allowed {
                throw .compressionRatioExceeded(path: file.path, limit: limits.maxCompressionRatio)
            }
            if keepingBytes { bytes.append(contentsOf: buffer[..<count]) }
        }
        return (bytes, archive_filter_bytes(archive, 0) - start, produced)
    }

    /// libarchive reports a ZIP entry's compression only in the format name, such as "ZIP 2.0 (deflation)".
    private var method: CompressionMethod? {
        let format = String(cString: archive_format_name(archive))
        if format.hasSuffix("(uncompressed)") { return .stored }
        if format.hasSuffix("(deflation)") { return .deflated }
        return nil
    }

    private var errorMessage: String {
        archive_error_string(archive).map { String(cString: $0) } ?? "unknown libarchive error"
    }
}
