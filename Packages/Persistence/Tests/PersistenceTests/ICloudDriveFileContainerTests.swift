import ComicStructure
import Foundation
import Testing
@testable import Persistence

/// The live iCloud Drive container, pointed at a plain temporary folder in place of the ubiquity container.
@Suite struct ICloudDriveFileContainerTests {
    /// Nested one level, so a path escaping it lands in a folder only this test uses.
    let root = FileManager.default.temporaryDirectory.appending(path: "ICloudDrive-\(UUID())/container")
    var container: ICloudDriveFileContainer { ICloudDriveFileContainer(containerURL: { [root] in root }) }
    let ref = FileRef("pageImage/\(UUID().uuidString).png")

    @Test func withoutTheUbiquityContainerICloudIsUnavailable() async throws {
        let signedOut = ICloudDriveFileContainer(containerURL: { nil })

        await #expect(throws: ICloudError.accountUnavailable) {
            try await signedOut.copyIn(tempFile("page", ext: "png"), as: ref)
        }
    }

    @Test func aCopiedInFileDownloadsToAnotherPlace() async throws {
        try await container.copyIn(tempFile("page one", ext: "png"), as: ref)
        let local = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).png")

        try await container.download(ref, to: local)

        #expect(try String(contentsOf: local, encoding: .utf8) == "page one")
    }

    /// Same as the fake: a file iCloud doesn't hold is `notFound`, which the store passes on from `fileURL`.
    @Test func aRemovedFileIsNotFoundAndRemovingItAgainIsNoError() async throws {
        try await container.copyIn(tempFile("page", ext: "png"), as: ref)

        try await container.remove(ref)
        try await container.remove(ref)

        await #expect(throws: PersistenceError.notFound(ref.id)) {
            try await container.download(ref, to: FileManager.default.temporaryDirectory.appending(path: "\(UUID()).png"))
        }
    }

    /// A plain folder isn't iCloud, so nothing in it is safely uploaded; a missing file isn't either.
    @Test func aFileICloudDoesNotHoldIsNotUploaded() async throws {
        try await container.copyIn(tempFile("page", ext: "png"), as: ref)

        #expect(try await container.isUploaded(ref) == false)
        #expect(try await container.isUploaded(FileRef("pageImage/\(UUID().uuidString).png")) == false)
    }

    @Test func aFileRefOutsideTheLayoutIsRefusedAndNothingIsWritten() async throws {
        let escaping = FileRef("../../escape.png")

        await #expect(throws: PersistenceError.invalidFileRef(escaping.id)) {
            try await container.copyIn(tempFile("page", ext: "png"), as: escaping)
        }
        #expect(!FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appending(path: "escape.png").path))
    }

    /// A sync that copied a file in but stopped before dequeuing it copies it in again next time.
    @Test func copyingInAgainReplacesTheFile() async throws {
        try await container.copyIn(tempFile("first", ext: "png"), as: ref)
        try await container.copyIn(tempFile("second", ext: "png"), as: ref)
        let local = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).png")

        try await container.download(ref, to: local)

        #expect(try String(contentsOf: local, encoding: .utf8) == "second")
    }
}
