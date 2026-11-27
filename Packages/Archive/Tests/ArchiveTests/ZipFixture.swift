import Foundation

/// Builds ZIP archives byte by byte, so tests can make the hostile and malformed archives that a ZIP writer refuses
/// to: unsafe names, lying sizes, encrypted flags, unknown methods, links and duplicate names.
struct ZipFixture {
    struct Entry {
        var name: [UInt8]
        /// The bytes as stored in the archive: already deflated when `method` is 8.
        var payload: Data
        var method: UInt16 = 0
        var flags: UInt16 = 0
        var crc: UInt32
        var uncompressedSize: UInt32
        var unixMode: UInt32 = 0o100644
    }

    var entries: [Entry] = []

    static let utf8NameFlag: UInt16 = 1 << 11
    static let encryptedFlag: UInt16 = 1

    mutating func stored(_ name: String, _ contents: Data = Data("x".utf8), flags: UInt16 = 0) {
        entries.append(Entry(name: Array(name.utf8), payload: contents, flags: flags,
                             crc: crc32(contents), uncompressedSize: UInt32(contents.count)))
    }

    /// A deflated entry whose headers declare `declaredSize` instead of the real expanded size when given.
    mutating func deflated(_ name: String, _ contents: Data, declaredSize: UInt32? = nil) throws {
        let payload = try (contents as NSData).compressed(using: .zlib) as Data
        entries.append(Entry(name: Array(name.utf8), payload: payload, method: 8, crc: crc32(contents),
                             uncompressedSize: declaredSize ?? UInt32(contents.count)))
    }

    var data: Data {
        var archive = Data()
        var central = Data()
        for entry in entries {
            let offset = UInt32(archive.count)
            archive.append(le32(0x0403_4b50))
            archive.append(header(entry))
            archive.append(contentsOf: entry.name)
            archive.append(entry.payload)

            central.append(le32(0x0201_4b50))
            central.append(le16(0x031E))
            central.append(header(entry))
            central.append(le16(0) + le16(0) + le16(0) + le32(entry.unixMode << 16) + le32(offset))
            central.append(contentsOf: entry.name)
        }
        let centralOffset = le32(UInt32(archive.count))
        let count = le16(UInt16(entries.count))
        archive.append(central)
        archive.append(le32(0x0605_4b50) + le16(0) + le16(0) + count + count
                       + le32(UInt32(central.count)) + centralOffset + le16(0))
        return archive
    }

    /// The fields that local and central headers share, from "version needed" to "extra field length".
    private func header(_ entry: Entry) -> Data {
        le16(20) + le16(entry.flags) + le16(entry.method) + le16(0) + le16(0x21) + le32(entry.crc)
            + le32(UInt32(entry.payload.count)) + le32(entry.uncompressedSize)
            + le16(UInt16(entry.name.count)) + le16(0)
    }
}

func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

private let crcTable: [UInt32] = (0..<256).map { (n: UInt32) in
    (0..<8).reduce(n) { crc, _ in crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
}

func crc32(_ data: Data) -> UInt32 {
    ~data.reduce(0xFFFF_FFFF) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
}

func temporaryFile(_ data: Data, named name: String = "fixture.zip") throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "ArchiveTests-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: name)
    try data.write(to: url)
    return url
}
