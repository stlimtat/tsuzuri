import Foundation
@testable import ComicStructure

/// The generated golden Pages under `Fixtures/golden` (see its README): images, ground truth, spreads,
/// manifest and licences, plus the checks that keep them trustworthy.
struct GoldenSet {
    static let schemaVersion = 1
    static let root = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../Fixtures/golden")
        .standardizedFileURL

    protocol Versioned: Decodable { var schemaVersion: Int { get } }

    struct GoldenBubble: Codable {
        let polygon: [[Double]]
        let textOrientation: TextOrientation
        let text: String
        let furigana: [RubySpan]
        let sfx: Bool
        let poisoned: Bool
    }

    struct GoldenPanel: Codable {
        let readingIndex: Int
        let polygon: [[Double]]
        let bubbles: [GoldenBubble]
        var shape: Polygon { Polygon(polygon.map { Point($0[0], $0[1]) }) }
    }

    /// Where a two-pages-in-one scan must be cut: vertically at `x` or horizontally at `y`.
    struct GoldenCut: Codable {
        let x: Double?
        let y: Double?
        var cut: Cut? { x.map { .vertical(x: $0) } ?? y.map { .horizontal(y: $0) } }
    }

    /// `ground-truth/pages/<id>.json`. Panels are in Page coordinates. A two-pages-in-one scan has an `expectedCut`,
    /// and its reading indexes count across the whole scan.
    struct GoldenPage: Codable, Versioned {
        let schemaVersion: Int
        let id: String
        let pixelSize: PixelSize
        let readingDirection: ReadingDirection
        let panels: [GoldenPanel]
        let expectedCut: GoldenCut?
    }

    /// `ground-truth/spreads/<id>.json`: two adjacent Pages, in Page order, and their two-Page Panels,
    /// in the canvas spanning both Pages (`Canvas`).
    struct GoldenSpread: Codable, Versioned {
        let schemaVersion: Int
        let id: String
        let pageIDs: [String]
        let readingDirection: ReadingDirection
        let panels: [GoldenPanel]
    }

    struct Manifest: Codable, Versioned {
        struct Entry: Codable { let id: String; let features: [String] }
        let schemaVersion: Int
        let pages: [Entry]
    }

    enum Problem: Hashable {
        case missingGroundTruth(String), missingImage(String)
        case missingLicence(String), licenceWithoutPage(String)
        case missingManifestEntry(String), manifestWithoutPage(String)
        case unreadable(String)
        case wrongSchemaVersion(String)
        case coordinateOutOfRange(String)
        case panelNotConvex(String)
        case bubbleOutsidePanel(String)
        case spreadMissingPage(String)
        case featureOnTooFewPages(String)
        case manifestDisagrees(String, feature: String)
    }

    /// The hard cases of specs/00-overview.md §8, as `manifest.json` names them; each must be on at least two Pages.
    static let requiredFeatures = [
        "verticalText", "horizontalText", "borderlessPanel", "slantedPanel", "twoPagePanel", "twoPagesInOneScan", "sfx",
        "smallFurigana", "denseDialogue", "poisonedText",
    ]

    let pages: [GoldenPage]
    let spreads: [GoldenSpread]
    let manifest: Manifest?
    let problems: [Problem]

    init(root: URL = GoldenSet.root) {
        var problems: [Problem] = []
        func load<T: Versioned>(_ type: T.Type, _ url: URL) -> T? {
            do {
                let value = try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
                if value.schemaVersion != Self.schemaVersion { problems.append(.wrongSchemaVersion(url.lastPathComponent)) }
                return value
            } catch {
                problems.append(.unreadable(url.lastPathComponent))
                return nil
            }
        }
        func files(_ dir: String, _ ext: String) -> [URL] {
            let urls = (try? FileManager.default.contentsOfDirectory(at: root.appending(path: dir), includingPropertiesForKeys: nil)) ?? []
            return urls.filter { $0.pathExtension == ext }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        let pageFiles = files("ground-truth/pages", "json").compactMap { url in
            load(GoldenPage.self, url).map { (url.lastPathComponent, $0) }
        }
        let spreadFiles = files("ground-truth/spreads", "json").compactMap { url in
            load(GoldenSpread.self, url).map { (url.lastPathComponent, $0) }
        }
        pages = pageFiles.map(\.1)
        spreads = spreadFiles.map(\.1)
        manifest = load(Manifest.self, root.appending(path: "manifest.json"))

        // Every Page has an image, ground truth, a manifest entry and a licence entry, and nothing else does.
        let imageIDs = Set(files("pages", "png").map { $0.deletingPathExtension().lastPathComponent })
        let truthIDs = Set(pages.map(\.id))
        problems += imageIDs.subtracting(truthIDs).sorted().map(Problem.missingGroundTruth)
        problems += truthIDs.subtracting(imageIDs).sorted().map(Problem.missingImage)
        let pageIDs = imageIDs.union(truthIDs)
        let licenceIDs = Self.licensedPageIDs(root.appending(path: "LICENSES.md"))
        problems += pageIDs.subtracting(licenceIDs).sorted().map(Problem.missingLicence)
        problems += licenceIDs.subtracting(pageIDs).sorted().map(Problem.licenceWithoutPage)
        for spread in spreads {
            problems += spread.pageIDs.filter { !pageIDs.contains($0) }.map(Problem.spreadMissingPage)
        }
        let manifestIDs = Set(manifest?.pages.map(\.id) ?? [])
        problems += pageIDs.subtracting(manifestIDs).sorted().map(Problem.missingManifestEntry)
        problems += manifestIDs.subtracting(pageIDs).sorted().map(Problem.manifestWithoutPage)
        // Features the ground truth records itself must agree with the manifest.
        let shownBy: [String: (GoldenPage) -> Bool] = [
            "poisonedText": { $0.panels.contains { $0.bubbles.contains(where: \.poisoned) } },
            "twoPagesInOneScan": { $0.expectedCut != nil },
        ]
        for page in pages {
            guard let listed = manifest?.pages.first(where: { $0.id == page.id })?.features else { continue }
            for (feature, shown) in shownBy.sorted(by: { $0.key < $1.key }) where listed.contains(feature) != shown(page) {
                problems.append(.manifestDisagrees(page.id, feature: feature))
            }
        }
        for feature in Self.requiredFeatures where (manifest?.pages ?? []).filter({ $0.features.contains(feature) }).count < 2 {
            problems.append(.featureOnTooFewPages(feature))
        }

        // Geometry: normalized coordinates, convex Panels, Bubbles within their Panel (invariant 5).
        let geometry = pageFiles.map { ($0.0, $0.1.panels) } + spreadFiles.map { ($0.0, $0.1.panels) }
        for (file, panels) in geometry {
            let polygons = panels.flatMap { [$0.polygon] + $0.bubbles.map(\.polygon) }
            if !polygons.joined().joined().allSatisfy((0...1).contains) { problems.append(.coordinateOutOfRange(file)) }
            // `isWellFormed` also rejects points off the Page; those are reported above.
            for panel in panels where !panel.shape.isWellFormed && panel.polygon.joined().allSatisfy((0...1).contains) {
                problems.append(.panelNotConvex(file))
            }
            for panel in panels where panel.shape.isWellFormed {
                for bubble in panel.bubbles
                where !bubble.polygon.allSatisfy({ panel.shape.contains(Point($0[0], $0[1]), tolerance: Invariants.bubbleTolerance) }) {
                    problems.append(.bubbleOutsidePanel(file))
                }
            }
        }
        self.problems = problems
    }

    /// Page ids in the `| Page | Licence | Source |` table of `LICENSES.md` that have a licence.
    static func licensedPageIDs(_ url: URL) -> Set<String> {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return Set(text.split(separator: "\n").compactMap { line -> String? in
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count > 2, cells[1] != "Page", !cells[1].hasPrefix("-"), !cells[2].isEmpty
            else { return nil }
            return cells[1]
        })
    }
}
