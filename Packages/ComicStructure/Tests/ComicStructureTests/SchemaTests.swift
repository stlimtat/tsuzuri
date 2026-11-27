import Foundation
import Testing
@testable import ComicStructure

@Suite struct SchemaTests {
    @Test func encodesWithSchemaVersionAndRoundTrips() throws {
        var work = makeWork()
        let ids = [work.chapters[0].panels[0].id]
        work.renders = [Render(chapterID: work.chapters[0].id, panelIDs: ids, status: .failed(reason: "refused"),
                               inputsHash: editor.inputsHash(panelIDs: ids, in: work), providerID: "p")]
        let data = try ComicSchema.encode(work)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == ComicSchema.currentVersion)
        #expect(try ComicSchema.decode(data) == work)
    }

    @Test func rejectsANewerSchemaVersion() throws {
        let data = Data(#"{"schemaVersion": 999, "work": {}}"#.utf8)
        #expect(throws: ComicSchema.Error.unsupportedVersion(999)) { try ComicSchema.decode(data) }
    }

    @Test func rejectsAWorkThatBreaksAnInvariant() throws {
        var work = makeWork()
        work.chapters[0].panels[0].readingIndex = 99
        let data = try JSONEncoder().encode(["schemaVersion": AnyEncodable(1), "work": AnyEncodable(work)])
        #expect(throws: EditError.self) { try ComicSchema.decode(data) }
    }

    /// 3.133 is a value that comes back as 3.132999… if anything on the way goes through Double.
    @Test(arguments: ["2.5", "0.1", "3.133", "10"])
    func aBookSummaryRoundTripsWithItsExactSeriesNumber(_ number: String) throws {
        let work = makeBook(series: BookSeries(name: "Kokoro", number: Decimal(string: number)))
        let decoded = try ComicSchema.decode(ComicSchema.encode(work))
        #expect(decoded == work)
        #expect(decoded.book?.series?.number?.description == number)
    }

    @Test func aRecordFromBeforeBookSummaryDecodesWithoutOne() throws {
        let data = Data(#"""
            {"schemaVersion":1,"work":{"cast":{"characters":[]},"chapters":[],"createdAt":0,
            "id":"0C4B4D1E-6F1A-4B53-9C1E-6A4F3E2D1B00","kind":"book","readingDirection":"leftToRight",
            "renders":[],"sourceLanguage":"ja","sources":[],"targetLanguage":"en","title":"Kokoro","updatedAt":0}}
            """#.utf8)
        let expected = Work(id: try #require(UUID(uuidString: "0C4B4D1E-6F1A-4B53-9C1E-6A4F3E2D1B00")),
                            createdAt: Date(timeIntervalSinceReferenceDate: 0), kind: .book, title: "Kokoro",
                            readingDirection: .leftToRight)

        let work = try ComicSchema.decode(data)

        #expect(work == expected)
        #expect(work.book == nil)
    }

    /// An older build decodes a record that has `book`, and its re-save drops it; a current build reads that back.
    @Test func anOlderBuildIgnoresBookSummaryAndItsResaveDecodesWithoutOne() throws {
        let work = makeBook(series: BookSeries(name: "Kokoro", number: 2))

        let older = try JSONDecoder().decode(OlderDocument.self, from: ComicSchema.encode(work))
        let resaved = try ComicSchema.decode(JSONEncoder().encode(older))

        var expected = work
        expected.book = nil
        #expect(resaved == expected)
    }

    @Test func aSeriesNumberThatIsNotANumberBreaksAnInvariant() throws {
        let work = makeBook(series: BookSeries(name: "Kokoro", number: .nan))
        #expect(throws: EditError.self) { try Invariants.validate(work) }
    }
}

func makeBook(series: BookSeries?) -> Work {
    Work(createdAt: fixedDate, kind: .book, title: "Kokoro", readingDirection: .leftToRight,
         sources: [Source(createdAt: fixedDate, fileName: "kokoro.epub", contentType: "org.idpf.epub-container",
                          byteSize: 1024, fileRef: FileRef("source/kokoro"))],
         book: BookSummary(authors: ["Natsume Sōseki"], series: series, cover: FileRef("cover/kokoro")))
}

/// A record as builds from before `Work.book` existed decode and re-encode it.
private struct OlderDocument: Codable {
    let schemaVersion: Int
    let work: OlderWork

    struct OlderWork: Codable {
        let id: UUID
        let createdAt: Date
        let updatedAt: Date
        let kind: WorkKind
        let title: String
        let readingDirection: ReadingDirection
        let sourceLanguage: String
        let targetLanguage: String
        let sources: [Source]
        let chapters: [Chapter]
        let cast: Cast
        let renders: [Render]
    }
}

struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
