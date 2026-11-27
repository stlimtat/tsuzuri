import Foundation

/// The model invariants from specs/R1/comic-structure.md, checked after every edit and on decode.
public enum Invariants {
    /// Bubble-within-Panel tolerance (invariant 5), in normalized units.
    public static let bubbleTolerance = 0.02

    public static func validate(_ work: Work) throws {
        func fail(_ message: String) -> EditError { .invariantViolated(message) }

        var seen = Set<UUID>()
        func unique(_ id: UUID) throws {
            guard seen.insert(id).inserted else { throw fail("duplicate id \(id)") }
        }

        let characterIDs = Set(work.cast.characters.map(\.id))
        for c in work.cast.characters {
            try unique(c.id)
            guard !c.referenceCrops.isEmpty else { throw fail("Character \(c.id) has no reference crop") }
        }

        for (ci, chapter) in work.chapters.enumerated() {
            try unique(chapter.id)
            guard chapter.index == ci else { throw fail("Chapter \(chapter.id) index \(chapter.index) ≠ \(ci)") }
            var pagePosition: [UUID: Int] = [:]
            for (pi, page) in chapter.pages.enumerated() {
                try unique(page.id)
                guard page.index == pi else { throw fail("Page \(page.id) index \(page.index) ≠ \(pi)") }
                pagePosition[page.id] = pi
            }
            // 2. Reading indexes unique and contiguous from 0 (stored in reading order).
            guard chapter.panels.map(\.readingIndex) == Array(chapter.panels.indices) else {
                throw fail("Chapter \(chapter.id) reading indexes not contiguous")
            }
            for panel in chapter.panels {
                try unique(panel.id)
                // 1. One or two Pages of this Chapter; two must be adjacent, in Page order.
                let positions = panel.pageIDs.compactMap { pagePosition[$0] }
                guard (1...2).contains(panel.pageIDs.count), positions.count == panel.pageIDs.count else {
                    throw fail("Panel \(panel.id) must cover 1 or 2 Pages of its Chapter")
                }
                if positions.count == 2, positions[1] != positions[0] + 1 {
                    throw fail("Panel \(panel.id) Pages are not adjacent")
                }
                guard panel.shape.isWellFormed else { throw fail("Panel \(panel.id) shape is not a convex polygon") }
                for bubble in panel.bubbles {
                    try unique(bubble.id)
                    guard bubble.shape.isWellFormed else { throw fail("Bubble \(bubble.id) shape is not a convex polygon") }
                    // 5. Bubble within its Panel.
                    guard bubble.shape.points.allSatisfy({ panel.shape.contains($0, tolerance: bubbleTolerance) }) else {
                        throw fail("Bubble \(bubble.id) lies outside Panel \(panel.id)")
                    }
                    if let line = bubble.line {
                        try unique(line.id)
                        // 4. Speaker is in the Cast.
                        if let speaker = line.speakerID, !characterIDs.contains(speaker) {
                            throw fail("Line \(line.id) Speaker \(speaker) is not in the Cast")
                        }
                    }
                }
            }
        }

        // 3. Holds for every Render that is not stale; stale Renders keep playing until the user re-renders.
        for render in work.renders {
            try unique(render.id)
            guard (1...10).contains(render.panelIDs.count) else { throw fail("Render \(render.id) must have 1–10 Panels") }
        }

        // JSONEncoder writes a NaN Decimal as a bare `NaN`, which is not JSON: the record would never decode again.
        if work.book?.series?.number?.isNaN == true { throw fail("Work \(work.id) series number is NaN") }
    }

    /// Invariant 3 at creation: 1–10 Panels of one Chapter, consecutive by reading index.
    static func renderPanelsAreConsecutive(_ render: Render, in work: Work) -> Bool {
        guard (1...10).contains(render.panelIDs.count),
              let chapter = work.chapters.first(where: { $0.id == render.chapterID }) else { return false }
        let indexes = render.panelIDs.map { id in chapter.panels.first { $0.id == id }?.readingIndex }
        guard let first = indexes.first ?? nil else { return false }
        return indexes == Array(first..<first + indexes.count).map(Optional.some)
    }
}
