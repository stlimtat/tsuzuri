import Archive
import Foundation
import Testing

/// `specs/R1/library-import.md` Safety: archives are untrusted, and every refusal is a typed error, never a crash.
@Suite struct HostileArchiveTests {
    func open(_ zip: ZipFixture, limits: ArchiveLimits = ArchiveLimits()) throws -> ArchiveReader {
        try ArchiveReader(contentsOf: temporaryFile(zip.data), limits: limits)
    }

    @Test(arguments: ["../escape.xhtml", "OEBPS/../../escape.xhtml", "..\\escape.xhtml", "OEBPS/.."])
    func pathTraversalIsRefused(_ name: String) {
        var zip = ZipFixture()
        zip.stored("OEBPS/fine.xhtml")
        zip.stored(name)
        expectUnsafePath(zip)
    }

    @Test(arguments: ["/etc/passwd", "\\\\server\\share\\x.xhtml", "C:\\Windows\\x.xhtml", "C:x.xhtml"])
    func absolutePathsAreRefused(_ name: String) {
        var zip = ZipFixture()
        zip.stored(name)
        expectUnsafePath(zip)
    }

    @Test func tenThousandEntriesAreRefused() {
        var zip = ZipFixture()
        for page in 0..<10_000 { zip.stored("p\(page).xhtml") }
        #expect(throws: ArchiveError.tooManyEntries(limit: 5_000)) { try open(zip) }
    }

    @Test func entriesUpToTheLimitOpen() throws {
        var zip = ZipFixture()
        for page in 0..<5_000 { zip.stored("p\(page).xhtml") }
        #expect(try open(zip).entries.count == 5_000)
    }

    /// 4 MiB of zeros deflates about a thousandfold.
    @Test func aZipBombIsStoppedByTheCompressionRatioLimit() throws {
        var zip = ZipFixture()
        zip.stored("mimetype", Data("application/epub+zip".utf8))
        try zip.deflated("bomb.xhtml", Data(count: 4 << 20))
        #expect(throws: ArchiveError.compressionRatioExceeded(path: "bomb.xhtml", limit: 100)) { try open(zip) }
    }

    @Test(arguments: [100, 4_000_000_000] as [UInt32])
    func anEntryWhoseHeaderLiesAboutItsSizeIsCorrupt(declaredSize: UInt32) throws {
        var zip = ZipFixture()
        try zip.deflated("OEBPS/text.xhtml", Data(String(repeating: "<p>text</p>", count: 50_000).utf8),
                         declaredSize: declaredSize)
        expectCorrupt(try temporaryFile(zip.data))
    }

    @Test func aSmallHighlyCompressibleFileIsNotMistakenForABomb() throws {
        var zip = ZipFixture()
        try zip.deflated("blank.css", Data(count: 512 << 10))
        #expect(try open(zip).entries.map(\.uncompressedSize) == [512 << 10])
    }

    @Test func archivesThatExpandPastTheTotalSizeLimitAreRefused() throws {
        var zip = ZipFixture()
        zip.stored("a.jpg", Data(count: 600_000))
        try zip.deflated("b.jpg", Data((0..<600_000).map { UInt8(truncatingIfNeeded: $0 &* 131) }))
        #expect(throws: ArchiveError.totalSizeExceeded(limit: 1_000_000)) {
            try open(zip, limits: ArchiveLimits(maxTotalUncompressedSize: 1_000_000))
        }
        #expect(try open(zip, limits: ArchiveLimits(maxTotalUncompressedSize: 1_200_000)).entries.count == 2)
    }

    @Test func aTruncatedArchiveIsCorrupt() throws {
        var zip = ZipFixture()
        zip.stored("mimetype", Data("application/epub+zip".utf8))
        try zip.deflated("OEBPS/text.xhtml", Data(String(repeating: "<p>text</p>", count: 500).utf8))
        let bytes = zip.data
        expectCorrupt(try temporaryFile(bytes.prefix(bytes.count / 2)))
    }

    @Test func anEntryWhoseBytesDoNotMatchItsChecksumIsCorrupt() throws {
        var zip = ZipFixture()
        zip.stored("OEBPS/text.xhtml", Data("<p>text</p>".utf8))
        zip.entries[0].crc ^= 1
        expectCorrupt(try temporaryFile(zip.data))
    }

    @Test(arguments: [Data(), Data("not an archive".utf8), Data(count: 4_096)])
    func aFileThatIsNotAZipIsCorrupt(_ bytes: Data) throws {
        expectCorrupt(try temporaryFile(bytes))
    }

    @Test func duplicatePathsAreRefused() {
        var zip = ZipFixture()
        zip.stored("OEBPS/content.opf")
        zip.stored("OEBPS/content.opf")
        #expect(throws: ArchiveError.duplicatePath("OEBPS/content.opf")) { try open(zip) }
    }

    @Test func pathsThatDifferOnlyInUnicodeNormalizationAreDuplicates() {
        let nfc = "OEBPS/が.xhtml".precomposedStringWithCanonicalMapping
        var zip = ZipFixture()
        zip.stored(nfc)
        zip.stored(nfc.decomposedStringWithCanonicalMapping)
        #expect(throws: ArchiveError.duplicatePath(nfc)) { try open(zip) }
    }

    @Test(arguments: [false, true])
    func japaneseNamesAreListedInNFCWhetherOrNotFlaggedUTF8(flagged: Bool) throws {
        let nfc = "OEBPS/本文/が.xhtml".precomposedStringWithCanonicalMapping
        var zip = ZipFixture()
        zip.stored(nfc.decomposedStringWithCanonicalMapping, flags: flagged ? ZipFixture.utf8NameFlag : 0)
        zip.stored(nfc.replacingOccurrences(of: "が", with: "ぱ"), flags: flagged ? ZipFixture.utf8NameFlag : 0)
        let reader = try open(zip)
        #expect(reader.entries.map { Array($0.path.utf8) } == [Array(nfc.utf8), Array(nfc.replacingOccurrences(of: "が", with: "ぱ").utf8)])
        #expect(try reader.data(for: nfc) == Data("x".utf8))
    }

    @Test func aNameThatIsNotUTF8IsRefused() {
        var zip = ZipFixture()
        zip.stored("x")
        let shiftJIS: [UInt8] = [0x83, 0x79, 0x81, 0x5B, 0x83, 0x57] // "ページ"
        zip.entries[0].name = shiftJIS
        #expect(throws: ArchiveError.unsafePath(String(decoding: shiftJIS, as: UTF8.self))) { try open(zip) }
    }

    @Test func encryptedEntriesAreRefused() {
        var zip = ZipFixture()
        zip.stored("OEBPS/secret.xhtml", flags: ZipFixture.encryptedFlag)
        #expect(throws: ArchiveError.unsupportedEntry("OEBPS/secret.xhtml")) { try open(zip) }
    }

    @Test(arguments: [12, 14, 93, 98] as [UInt16])
    func entriesCompressedWithAnotherMethodAreRefused(method: UInt16) {
        var zip = ZipFixture()
        zip.stored("OEBPS/text.xhtml")
        zip.entries[0].method = method
        #expect(throws: ArchiveError.unsupportedEntry("OEBPS/text.xhtml")) { try open(zip) }
    }

    @Test func symbolicLinksAreRefused() {
        var zip = ZipFixture()
        zip.stored("OEBPS/link.xhtml", Data("/etc/passwd".utf8))
        zip.entries[0].unixMode = 0o120777
        #expect(throws: ArchiveError.unsupportedEntry("OEBPS/link.xhtml")) { try open(zip) }
    }

    @Test func directoriesAreNotListed() throws {
        var zip = ZipFixture()
        zip.stored("OEBPS/", Data())
        zip.entries[0].unixMode = 0o040755
        zip.stored("OEBPS/text.xhtml")
        #expect(try open(zip).entries.map(\.path) == ["OEBPS/text.xhtml"])
    }
}

/// Unsafe-path refusals report the name as libarchive decoded it, which may already have backslashes turned into
/// slashes, so only the case is checked.
func expectUnsafePath(_ zip: ZipFixture, sourceLocation: SourceLocation = #_sourceLocation) {
    let error = #expect(throws: ArchiveError.self, sourceLocation: sourceLocation) {
        try ArchiveReader(contentsOf: temporaryFile(zip.data))
    }
    guard case .unsafePath = error else {
        Issue.record("Expected an unsafe path, got \(String(describing: error))", sourceLocation: sourceLocation)
        return
    }
}

func expectCorrupt(_ url: URL, sourceLocation: SourceLocation = #_sourceLocation) {
    let error = #expect(throws: ArchiveError.self, sourceLocation: sourceLocation) { try ArchiveReader(contentsOf: url) }
    guard case .corrupt = error else {
        Issue.record("Expected a corrupt archive, got \(String(describing: error))", sourceLocation: sourceLocation)
        return
    }
}
