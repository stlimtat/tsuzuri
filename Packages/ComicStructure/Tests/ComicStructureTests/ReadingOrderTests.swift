import Foundation
import Testing
@testable import ComicStructure

/// Golden set: reading order must match ground truth for ≥95% of Panels, given ground-truth Panel shapes.
@Suite struct ReadingOrderTests {
    struct GroundTruth: Decodable {
        struct GoldenPage: Decodable {
            struct GoldenPanel: Decodable {
                let rect: [Double]?
                let polygon: [[Double]]?
                var shape: Polygon {
                    if let r = rect { return .rect(Rect(minX: r[0], minY: r[1], maxX: r[2], maxY: r[3])) }
                    return Polygon((polygon ?? []).map { Point($0[0], $0[1]) })
                }
            }
            let id: String
            let readingDirection: ReadingDirection
            let panels: [GoldenPanel]
        }
        let pages: [GoldenPage]
    }

    static let fixture = URL(filePath: #filePath)
        .deletingLastPathComponent().appending(path: "../../../../Fixtures/golden/ground-truth/reading-order.json")

    @Test func matchesGoldenSetGroundTruth() throws {
        let truth = try JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: Self.fixture))
        var matched = 0, total = 0
        for golden in truth.pages {
            let page = makePage(0)
            // Panels are stored reversed below so the algorithm cannot lean on input order.
            let panels = golden.panels.enumerated().map { i, p in
                Panel(id: derivedID(page.id, "\(i)"), pageIDs: [page.id], shape: p.shape, readingIndex: i)
            }
            #expect(panels.allSatisfy { $0.shape.isWellFormed }, "\(golden.id): malformed polygon")
            let chapter = Chapter(title: golden.id, index: 0, pages: [page], panels: panels.reversed())
            let order = editor.readingOrder(for: chapter, direction: golden.readingDirection)
            let expected = panels.map(\.id)
            let hits = zip(order, expected).filter { $0 == $1 }.count
            if hits != expected.count { print("reading order mismatch on \(golden.id)") }
            matched += hits
            total += expected.count
        }
        #expect(total >= 50)
        #expect(Double(matched) / Double(total) >= 0.95, "\(matched)/\(total) Panels in ground-truth order")
    }

    /// The generated golden Pages: each Page on its own, except a spread's Pages, read together with their
    /// two-Page Panels.
    @Test func matchesGeneratedPagesGroundTruth() throws {
        let golden = GoldenSet()
        let spreadPageIDs = Set(golden.spreads.flatMap(\.pageIDs))
        let units: [(name: String, direction: ReadingDirection, pages: [GoldenSet.GoldenPage], canvas: [GoldenSet.GoldenPanel])] =
            golden.pages.filter { !spreadPageIDs.contains($0.id) }.map { ($0.id, $0.readingDirection, [$0], []) }
            + golden.spreads.map { spread in
                (spread.id, spread.readingDirection, spread.pageIDs.compactMap { id in golden.pages.first { $0.id == id } },
                 spread.panels)
            }
        var matched = 0, total = 0
        for unit in units {
            let pages = unit.pages.indices.map(makePage)
            var panels = unit.canvas.map { p in
                Panel(pageIDs: pages.map(\.id), shape: p.shape, readingIndex: p.readingIndex)
            }
            for (page, golden) in zip(pages, unit.pages) {
                panels += golden.panels.map { Panel(pageIDs: [page.id], shape: $0.shape, readingIndex: $0.readingIndex) }
            }
            let expected = panels.sorted { $0.readingIndex < $1.readingIndex }.map(\.id)
            let chapter = Chapter(title: unit.name, index: 0, pages: pages, panels: panels.reversed())
            let order = editor.readingOrder(for: chapter, direction: unit.direction)
            let hits = zip(order, expected).filter { $0 == $1 }.count
            if hits != expected.count { print("reading order mismatch on \(unit.name)") }
            matched += hits
            total += expected.count
        }
        #expect(total >= 15)  // the generated Pages loaded
        #expect(Double(matched) / Double(total) >= 0.95, "\(matched)/\(total) Panels in ground-truth order")
    }

    @Test func recomputeReadingOrderAppliesGeometry() throws {
        var work = makeWork()
        // Swap the two Panels on Page 0 so the left one comes first, then recompute.
        work.chapters[0].panels[0].readingIndex = 1
        work.chapters[0].panels[1].readingIndex = 0
        work.chapters[0].panels.swapAt(0, 1)
        let result = try #require(try editor.apply(.recomputeReadingOrder(chapterID: work.chapters[0].id), to: work).work)
        #expect(result.chapters[0].panels.prefix(2).map(\.shape.bounds.minX) == [0.5, 0])
    }
}

@Suite struct ReadingOrderOverrideTests {
    @Test func recomputeKeepsPanelsTheUserMoved() throws {
        let work = makeWork()
        let ch = work.chapters[0]
        let left = ch.panels[1]  // left Panel of Page 0; geometry puts it second (right-to-left)
        let moved = try #require(try editor.apply(.movePanel(left.id, toReadingIndex: 0), to: work).work)
        #expect(moved.chapters[0].panels[0].readingOrderSource == .user)

        // Scramble the rest so recompute has detected Panels to reorder around the pin.
        var scrambled = moved
        scrambled.chapters[0].panels[1...].reverse()
        for i in scrambled.chapters[0].panels.indices { scrambled.chapters[0].panels[i].readingIndex = i }

        let result = try #require(try editor.apply(.recomputeReadingOrder(chapterID: ch.id), to: scrambled).work)
        var expected = ch.panels.map(\.id)
        expected.swapAt(0, 1)
        #expect(result.chapters[0].panels.map(\.id) == expected)
    }
}
