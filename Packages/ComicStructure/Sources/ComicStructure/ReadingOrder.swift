import Foundation

/// Reading order from geometry by recursive XY-cut: split into rows top to bottom first, then into columns
/// in reading direction, and recurse. Right-to-left reads columns right to left.
enum ReadingOrder {
    /// How far bounding boxes may overlap and still count as separated (slanted or borderless Panels).
    static let cutTolerance = 0.03

    struct Region { let id: UUID; let bounds: Rect }

    /// Panel order for a Chapter: Page by Page, then by geometry within the Page.
    /// A two-Page Panel is placed on its first Page as spanning the Page's full width.
    static func panels(of chapter: Chapter, direction: ReadingDirection) -> [UUID] {
        let pagePosition = Dictionary(uniqueKeysWithValues: chapter.pages.enumerated().map { ($1.id, $0) })
        let byPage = Dictionary(grouping: chapter.panels) { $0.pageIDs.compactMap { pagePosition[$0] }.min() ?? 0 }
        return byPage.keys.sorted().flatMap { key in
            order(byPage[key]!.map { panel in
                var bounds = panel.shape.bounds
                if panel.pageIDs.count == 2, direction != .verticalScroll { bounds.minX = 0; bounds.maxX = 1 }
                return Region(id: panel.id, bounds: bounds)
            }, direction: direction)
        }
    }

    static func order(_ regions: [Region], direction: ReadingDirection) -> [UUID] {
        if direction == .verticalScroll {
            return regions.sorted { ($0.bounds.minY, $0.bounds.minX) < ($1.bounds.minY, $1.bounds.minX) }.map(\.id)
        }
        return xyCut(regions, direction: direction)
    }

    private static func xyCut(_ regions: [Region], direction: ReadingDirection) -> [UUID] {
        guard regions.count > 1 else { return regions.map(\.id) }
        let rows = split(regions, min: \.minY, max: \.maxY)
        if rows.count > 1 { return rows.flatMap { xyCut($0, direction: direction) } }
        let columns = split(regions, min: \.minX, max: \.maxX)
        if columns.count > 1 {
            let ordered = direction == .rightToLeft ? columns.reversed() : columns
            return ordered.flatMap { xyCut($0, direction: direction) }
        }
        // No clean cut: fall back to top-to-bottom, then by reading direction.
        let rtl = direction == .rightToLeft
        return regions.sorted {
            if abs($0.bounds.minY - $1.bounds.minY) > cutTolerance { return $0.bounds.minY < $1.bounds.minY }
            return rtl ? $0.bounds.midX > $1.bounds.midX : $0.bounds.midX < $1.bounds.midX
        }.map(\.id)
    }

    /// Groups regions separated by gaps along one axis, in ascending order.
    private static func split(_ regions: [Region], min: KeyPath<Rect, Double>, max: KeyPath<Rect, Double>) -> [[Region]] {
        let sorted = regions.sorted { $0.bounds[keyPath: min] < $1.bounds[keyPath: min] }
        var groups: [[Region]] = []
        var reach = -Double.infinity
        for region in sorted {
            if groups.isEmpty || region.bounds[keyPath: min] >= reach - cutTolerance { groups.append([]) }
            groups[groups.count - 1].append(region)
            reach = Swift.max(reach, region.bounds[keyPath: max])
        }
        return groups
    }
}
