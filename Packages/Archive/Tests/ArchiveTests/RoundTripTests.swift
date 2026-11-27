import Archive
import Foundation
import Testing

@Suite struct RoundTripTests {
    let items = [
        ArchiveItem(path: "mimetype", contents: Data("application/epub+zip".utf8), method: .stored),
        ArchiveItem(path: "META-INF/container.xml", contents: Data(String(repeating: "<rootfile/>", count: 200).utf8),
                    method: .deflated),
        ArchiveItem(path: "OEBPS/本文/が.xhtml", contents: Data("<p>吾輩は猫である。</p>".utf8), method: .deflated),
        ArchiveItem(path: "OEBPS/cover.jpg", contents: Data((0..<5_000).map { UInt8(truncatingIfNeeded: $0 &* 131) }),
                    method: .stored),
        ArchiveItem(path: "OEBPS/empty.css", contents: Data(), method: .deflated),
    ]

    func written(_ items: [ArchiveItem]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).zip")
        try ArchiveWriter.write(items, to: url)
        return url
    }

    @Test func writingThenReadingKeepsOrderPathsBytesAndMethods() throws {
        let reader = try ArchiveReader(contentsOf: written(items))
        #expect(reader.entries.map(\.path) == items.map(\.path))
        #expect(reader.entries.map(\.method) == items.map(\.method))
        for item in items {
            #expect(try reader.data(for: item.path) == item.contents)
        }
    }

    @Test func listedSizesAreWhatTheEntriesHoldAndTakeUp() throws {
        let entries = try ArchiveReader(contentsOf: written(items)).entries
        #expect(entries.map(\.uncompressedSize) == items.map { Int64($0.contents.count) })
        let container = try #require(entries.first { $0.path == "META-INF/container.xml" })
        #expect(container.compressedSize > 0 && container.compressedSize < container.uncompressedSize)
        for entry in entries where entry.method == .stored {
            #expect(entry.compressedSize == entry.uncompressedSize)
        }
    }

    /// EPUB readers find `mimetype` at a fixed offset: OCF forbids an extra field before its contents.
    @Test func aStoredFirstEntryStartsRightAfterItsName() throws {
        let bytes = try Data(contentsOf: written(items))
        #expect(bytes[8..<10] == le16(0), "stored")
        #expect(bytes[26..<28] == le16(8), "name length")
        #expect(bytes[28..<30] == le16(0), "extra field length")
        #expect(bytes[30..<58] == Data("mimetypeapplication/epub+zip".utf8))
    }

    @Test(arguments: ["../escape.xhtml", "/absolute.xhtml", "C:\\absolute.xhtml", "", "a//b.xhtml", "folder/"])
    func theWriterRefusesAnUnsafePathAndLeavesNoFile(_ path: String) {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).zip")
        #expect(throws: ArchiveError.unsafePath(path)) {
            try ArchiveWriter.write(items + [ArchiveItem(path: path, contents: Data(), method: .stored)], to: url)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func theWriterRefusesTwoItemsWithOnePath() {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).zip")
        #expect(throws: ArchiveError.duplicatePath("mimetype")) { try ArchiveWriter.write(items + items, to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func readingAPathTheArchiveLacksFails() throws {
        let reader = try ArchiveReader(contentsOf: written(items))
        #expect(throws: ArchiveError.entryNotFound("OEBPS/missing.xhtml")) {
            try reader.data(for: "OEBPS/missing.xhtml")
        }
    }

    @Test func defaultLimitsAreThoseOfTheImportSpec() {
        let limits = ArchiveLimits()
        #expect(limits.maxEntryCount == 5_000)
        #expect(limits.maxTotalUncompressedSize == 4 * 1024 * 1024 * 1024)
        #expect(limits.maxCompressionRatio == 100)
    }
}
