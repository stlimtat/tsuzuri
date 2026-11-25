import ComicStructure
import Foundation

/// The app's iCloud Drive ubiquity container, laid out like a Library root's `files/`: every path comes from a
/// FileRef that passed `validate()`, so a tampered record can't name a file outside it.
public struct ICloudDriveFileContainer: UbiquitousFileContainer {
    /// The ubiquity container's folder, or nil while iCloud Drive is unavailable to the app.
    private let containerURL: @Sendable () -> URL?

    /// The live container. Its folder is looked up on each request (never on the main thread: the lookup can
    /// block), so signing in to iCloud later starts working without a relaunch.
    public init(containerIdentifier: String) {
        containerURL = { FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) }
    }

    init(containerURL: @escaping @Sendable () -> URL?) { self.containerURL = containerURL }

    /// Where `ref` lives in the container; throws while iCloud Drive is unavailable or if `ref` is invalid.
    private func url(for ref: FileRef) throws -> URL {
        guard let root = containerURL() else { throw ICloudError.accountUnavailable }
        return try LibraryLayout(root: root).fileURL(ref)
    }

    /// Copies the file in under a coordinated write, so iCloud uploads the finished file, never a partial one.
    public func copyIn(_ local: URL, as ref: FileRef) async throws {
        let destination = try url(for: ref)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinate(writing: destination, options: .forReplacing) { url in
            try Self.replace(url, withCopyOf: local)
        }
    }

    /// Asks iCloud for the file, waits until this device has its current version, then copies it out.
    public func download(_ ref: FileRef, to local: URL) async throws {
        let source = try url(for: ref)
        // Every file iCloud holds is ubiquitous, downloaded or not; anything else is a plain local file.
        if FileManager.default.isUbiquitousItem(at: source) {
            try await waitUntilDownloaded(source)
        } else if !FileManager.default.fileExists(atPath: source.path) {
            throw PersistenceError.notFound(ref.id)
        }
        try coordinate(reading: source) { url in try Self.replace(local, withCopyOf: url) }
    }

    /// How long a download may take before sync gives up on it for now.
    static let downloadTimeout = Duration.seconds(120)

    private func waitUntilDownloaded(_ url: URL) async throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = ContinuousClock.now + Self.downloadTimeout
        while true {
            var url = url
            url.removeAllCachedResourceValues()
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey])
            if let error = values.ubiquitousItemDownloadingError { throw error }
            if values.ubiquitousItemDownloadingStatus == .current { return }
            guard ContinuousClock.now < deadline else { throw ICloudError.accountUnavailable }
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    private static func replace(_ destination: URL, withCopyOf source: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func coordinate(writing url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options, error: &coordinationError) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }

    private func coordinate(reading url: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }
    /// Whether iCloud has the file's current contents; false for a file the container lacks.
    public func isUploaded(_ ref: FileRef) async throws -> Bool {
        let file = try url(for: ref)
        guard FileManager.default.isUbiquitousItem(at: file) else { return false }
        return try file.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey]).ubiquitousItemIsUploaded ?? false
    }
    /// Removes the file under a coordinated delete; iCloud then removes it from every device.
    public func remove(_ ref: FileRef) async throws {
        let target = try url(for: ref)
        try coordinate(writing: target, options: .forDeleting) { url in
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
}
