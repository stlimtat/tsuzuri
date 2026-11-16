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
}

struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
