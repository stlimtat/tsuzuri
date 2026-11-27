import ComicStructure
import Foundation

/// Where a Library keeps things under its root on this device: one JSON record per Work in `works/`,
/// files in `files/<kind>/`. Shared by every store so they agree on paths and on which FileRefs are valid.
struct LibraryLayout: Sendable {
    let root: URL
    var worksDir: URL { root.appending(path: "works", directoryHint: .isDirectory) }
    var filesDir: URL { root.appending(path: "files", directoryHint: .isDirectory) }

    func createDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: worksDir, withIntermediateDirectories: true)
        for kind in FileKind.allCases {
            try fm.createDirectory(at: filesDir.appending(path: kind.rawValue), withIntermediateDirectories: true)
        }
    }

    func recordURL(_ id: Work.ID) -> URL { worksDir.appending(path: "\(id.uuidString).json") }

    /// The local path of a file, after checking its FileRef strictly.
    func fileURL(_ ref: FileRef) throws -> URL {
        try ref.validate()
        return filesDir.appending(path: ref.id)
    }
}

extension FileRef {
    /// Accepts only `<kind>/<uuid>` with an optional short alphanumeric extension, so a tampered record
    /// can't point outside the Library.
    func validate() throws {
        let parts = id.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, FileKind(rawValue: String(parts[0])) != nil else { throw PersistenceError.invalidFileRef(id) }
        let name = parts[1].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard UUID(uuidString: String(name[0])) != nil,
              name.count == 1 || (1...10).contains(name[1].count) && name[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { throw PersistenceError.invalidFileRef(id) }
    }
}

extension Work {
    /// Every file this Work references.
    var fileRefs: Set<FileRef> {
        var refs = Set(sources.map(\.fileRef))
        refs.formUnion(chapters.flatMap(\.pages).map(\.imageRef))
        refs.formUnion(cast.characters.flatMap(\.referenceCrops))
        refs.formUnion(renders.compactMap(\.videoRef))
        if let cover = book?.cover { refs.insert(cover) }
        return refs
    }
}
