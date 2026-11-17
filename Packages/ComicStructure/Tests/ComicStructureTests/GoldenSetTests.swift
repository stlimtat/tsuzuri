import Foundation
import Testing
@testable import ComicStructure

/// Golden set validation: the committed Pages must be trustworthy, and each check must catch its break.
@Suite struct GoldenSetTests {
    @Test func committedGoldenSetIsValid() {
        let golden = GoldenSet()
        #expect(golden.problems.isEmpty, "\(golden.problems)")
        #expect(golden.pages.count >= 5)
        let orientations = Set(golden.pages.flatMap { $0.panels.flatMap { $0.bubbles.map(\.textOrientation) } })
        #expect(orientations == [.vertical, .horizontal])
        #expect(golden.spreads.count >= 1)
    }
}

/// Each check must catch its break: a copy of the committed golden set, broken one way, reports that problem.
@Suite struct GoldenSetValidationTests {
    /// Validates a copy of the committed golden set after `breakIt` has changed it.
    func problems(after breakIt: (URL) throws -> Void) throws -> [GoldenSet.Problem] {
        let copy = FileManager.default.temporaryDirectory.appending(path: "golden-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: copy) }
        try FileManager.default.copyItem(at: GoldenSet.root, to: copy)
        try breakIt(copy)
        return GoldenSet(root: copy).problems
    }

    /// Rewrites one JSON file of the copy.
    func edit(_ root: URL, _ path: String, _ change: (inout [String: Any]) -> Void) throws {
        let url = root.appending(path: path)
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        change(&json)
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }

    @Test func pageWithoutGroundTruth() throws {
        let found = try problems { try FileManager.default.removeItem(at: $0.appending(path: "ground-truth/pages/p01-vertical-grid.json")) }
        #expect(found == [.missingGroundTruth("p01-vertical-grid")])
    }

    @Test func strayFileIsNotAPage() throws {
        let found = try problems { try Data().write(to: $0.appending(path: "pages/.DS_Store")) }
        #expect(found == [])
    }

    @Test func groundTruthWithoutPage() throws {
        let found = try problems { try FileManager.default.removeItem(at: $0.appending(path: "pages/p02-horizontal-western.png")) }
        #expect(found == [.missingImage("p02-horizontal-western")])
    }

    @Test func pageWithoutLicence() throws {
        let found = try problems { root in
            let url = root.appending(path: "LICENSES.md")
            let text = try String(contentsOf: url, encoding: .utf8)
            try text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.contains("p03-slanted-sfx") }
                .joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        #expect(found == [.missingLicence("p03-slanted-sfx")])
    }

    @Test func licenceEntryWithoutLicence() throws {
        let found = try problems { root in
            let url = root.appending(path: "LICENSES.md")
            try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(of: "| p03-slanted-sfx | self-drawn |", with: "| p03-slanted-sfx |  |")
                .write(to: url, atomically: true, encoding: .utf8)
        }
        #expect(found == [.missingLicence("p03-slanted-sfx")])
    }

    @Test func licenceWithoutPage() throws {
        let found = try problems { root in
            let handle = try FileHandle(forWritingTo: root.appending(path: "LICENSES.md"))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("| p99-not-drawn | self-drawn | generate.swift |\n".utf8))
            try handle.close()
        }
        #expect(found == [.licenceWithoutPage("p99-not-drawn")])
    }

    @Test func pageWithoutManifestEntry() throws {
        let found = try problems { root in
            try edit(root, "manifest.json") { json in
                json["pages"] = (json["pages"] as! [[String: Any]]).filter { $0["id"] as? String != "p04-borderless-poisoned" }
            }
        }
        #expect(found == [.missingManifestEntry("p04-borderless-poisoned")])
    }

    @Test func manifestEntryWithoutPage() throws {
        let found = try problems { root in
            try edit(root, "manifest.json") { json in
                json["pages"] = json["pages"] as! [[String: Any]] + [["id": "p99-not-drawn", "features": ["sfx"]]]
            }
        }
        #expect(found == [.manifestWithoutPage("p99-not-drawn")])
    }

    @Test func unreadableGroundTruth() throws {
        let found = try problems { try Data("{".utf8).write(to: $0.appending(path: "ground-truth/spreads/s01-two-page-panel.json")) }
        #expect(found == [.unreadable("s01-two-page-panel.json")])
    }

    @Test func wrongSchemaVersion() throws {
        let found = try problems { try edit($0, "ground-truth/pages/p01-vertical-grid.json") { $0["schemaVersion"] = 2 } }
        #expect(found == [.wrongSchemaVersion("p01-vertical-grid.json")])
    }

    /// Changes Panel `panel`'s polygon in a ground-truth file.
    func editPanel(_ root: URL, _ path: String, panel: Int, _ change: (inout [[Double]]) -> Void) throws {
        try edit(root, path) { json in
            var panels = json["panels"] as! [[String: Any]]
            var polygon = panels[panel]["polygon"] as! [[Double]]
            change(&polygon)
            panels[panel]["polygon"] = polygon
            json["panels"] = panels
        }
    }

    @Test func coordinateOutsidePage() throws {
        // Panel 1 is [0.51, 0.02, 0.98, 0.32]; pulling its top-right corner off the Page keeps it convex.
        let found = try problems {
            try editPanel($0, "ground-truth/pages/p02-horizontal-western.json", panel: 1) { $0[1] = [1.2, 0.02] }
        }
        #expect(found == [.coordinateOutOfRange("p02-horizontal-western.json")])
    }

    @Test func panelNotConvex() throws {
        // Panel 2 is [0.02, 0.34, 0.98, 0.64]; a dent in its bottom edge stays clear of its Bubble.
        let found = try problems {
            try editPanel($0, "ground-truth/pages/p02-horizontal-western.json", panel: 2) { $0.insert([0.80, 0.55], at: 3) }
        }
        #expect(found == [.panelNotConvex("p02-horizontal-western.json")])
    }

    /// Shifts Bubble 0 of Panel `panel` in a ground-truth file right by `dx`.
    func shiftBubble(_ root: URL, _ path: String, panel: Int, dx: Double) throws {
        try edit(root, path) { json in
            var panels = json["panels"] as! [[String: Any]]
            var bubbles = panels[panel]["bubbles"] as! [[String: Any]]
            bubbles[0]["polygon"] = (bubbles[0]["polygon"] as! [[Double]]).map { [$0[0] + dx, $0[1]] }
            panels[panel]["bubbles"] = bubbles
            json["panels"] = panels
        }
    }

    // p01 Panel 1 is [0.02, 0.02, 0.49, 0.49]; its Bubble spans x 0.30…0.44.
    @Test func bubbleOutsideItsPanel() throws {
        let found = try problems { try shiftBubble($0, "ground-truth/pages/p01-vertical-grid.json", panel: 1, dx: 0.08) }
        #expect(found == [.bubbleOutsidePanel("p01-vertical-grid.json")])
    }

    @Test func bubbleWithinTwoPercentOfItsPanel() throws {
        let found = try problems { try shiftBubble($0, "ground-truth/pages/p01-vertical-grid.json", panel: 1, dx: 0.065) }
        #expect(found == [])
    }

    @Test func spreadReferencesMissingPage() throws {
        let found = try problems {
            try edit($0, "ground-truth/spreads/s01-two-page-panel.json") { $0["pageIDs"] = ["p05-spread-right", "p99-not-drawn"] }
        }
        #expect(found == [.spreadMissingPage("p99-not-drawn")])
    }
}
