internal import CArchive
import Foundation

public enum ArchiveWriter {
    /// Writes `items` as a new ZIP archive at `url`, replacing any file there, in the given order and each with its
    /// own compression method. Entries carry no timestamps, owners or extra fields, so a stored first entry's bytes
    /// start right after its name, as EPUB requires of `mimetype`. On failure no file is left at `url`.
    public static func write(_ items: [ArchiveItem], to url: URL) throws(ArchiveError) {
        var paths = Set<String>()
        let validated = try items.map { item throws(ArchiveError) in
            guard let path = archivePath(item.path) else { throw .unsafePath(item.path) }
            guard paths.insert(path).inserted else { throw .duplicatePath(path) }
            return (path: path, item: item)
        }

        guard let archive = archive_write_new() else { throw .writeFailed("libarchive could not allocate a writer") }
        defer { archive_write_free(archive) }
        try check(archive_write_set_format_zip(archive), archive)
        try check(url.withUnsafeFileSystemRepresentation { archive_write_open_filename(archive, $0) }, archive)
        do throws(ArchiveError) {
            for (path, item) in validated {
                try write(item, at: path, to: archive)
            }
            try check(archive_write_close(archive), archive)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func write(_ item: ArchiveItem, at path: String, to archive: OpaquePointer) throws(ArchiveError) {
        switch item.method {
        case .stored: try check(archive_write_zip_set_compression_store(archive), archive)
        case .deflated: try check(archive_write_zip_set_compression_deflate(archive), archive)
        }
        guard let entry = archive_entry_new() else { throw .writeFailed("libarchive could not allocate an entry") }
        defer { archive_entry_free(entry) }
        archive_entry_copy_pathname(entry, path)
        archive_entry_set_filetype(entry, 0o100000)
        archive_entry_set_perm(entry, 0o644)
        archive_entry_set_size(entry, Int64(item.contents.count))
        try check(archive_write_header(archive, entry), archive)
        let complete = item.contents.withUnsafeBytes { contents in
            guard let base = contents.baseAddress else { return true }
            var offset = 0
            while offset < contents.count {
                let written = archive_write_data(archive, base + offset, contents.count - offset)
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
        guard complete else { throw .writeFailed(errorMessage(archive)) }
        try check(archive_write_finish_entry(archive), archive)
    }

    private static func check(_ status: Int32, _ archive: OpaquePointer) throws(ArchiveError) {
        guard status == ARCHIVE_OK else { throw .writeFailed(errorMessage(archive)) }
    }

    private static func errorMessage(_ archive: OpaquePointer) -> String {
        archive_error_string(archive).map { String(cString: $0) } ?? "unknown libarchive error"
    }
}
