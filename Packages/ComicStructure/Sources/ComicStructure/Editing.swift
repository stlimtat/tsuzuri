import CryptoKit
import Foundation

public enum Cut: Hashable, Sendable {
    /// A vertical cut line at `x` (normalized), e.g. for a two-pages-in-one scan.
    case vertical(x: Double)
    /// A horizontal cut line at `y` (normalized).
    case horizontal(y: Double)
}

public indirect enum ComicOperation: Hashable, Sendable {
    // Chapter
    /// Moves `atPage` and every following Page into a new Chapter right after this one.
    case splitChapter(UUID, atPage: UUID, newChapterID: UUID, newTitle: String)
    case mergeChapterWithNext(UUID)
    case renameChapter(UUID, title: String)
    case moveChapter(UUID, toIndex: Int)
    case setStorySummary(UUID, String?)
    // Page (no Page merge)
    /// Replaces the Page with two halves, in reading direction. Its Panels move to the half that holds them; a Panel
    /// across the cut becomes a two-Page Panel when the cut matches the reading direction (e.g. a two-pages-in-one scan).
    case splitPage(UUID, cut: Cut, firstPageID: UUID, secondPageID: UUID)
    /// Moves a Page within its Chapter or to another one; `atIndex` is its position in the destination afterwards.
    case movePage(UUID, toChapter: UUID, atIndex: Int)
    // Panel
    /// Inserts the Panel at its `readingIndex` (clamped) in the Chapter's reading order.
    case addPanel(Panel, chapterID: UUID)
    case deletePanel(UUID)
    case reshapePanel(UUID, Polygon)
    /// Cuts along the line through `from` and `to`. The part left of from→to keeps the id; the other part follows it in reading order.
    case splitPanel(UUID, from: Point, to: Point, newPanelID: UUID)
    /// Merges the second Panel into the first (convex hull); they must be in one Chapter on the same or adjacent Pages.
    case mergePanels(UUID, UUID)
    case movePanel(UUID, toReadingIndex: Int)
    case recomputeReadingOrder(chapterID: UUID)
    // Bubble
    case addBubble(Bubble, panelID: UUID)
    case deleteBubble(UUID)
    case reshapeBubble(UUID, Polygon)
    case setTextOrientation(bubbleID: UUID, TextOrientation)
    // Line
    case setLine(bubbleID: UUID, Line?)
    case editSourceText(bubbleID: UUID, String)
    case editTranslation(bubbleID: UUID, String)
    case setSpeaker(bubbleID: UUID, UUID?)
    // Cast
    case addCharacter(Character)
    case updateCharacter(Character)
    /// Also clears the Character as Speaker on every Line.
    case deleteCharacter(UUID)
    // Render
    case addRender(Render)
    // Undo/redo
    case restore(Work)
    /// The same operation, with the user's consent to split the Panels it reported in `.requiresConfirmation`.
    case confirmed(ComicOperation)
}

public enum EditResult: Equatable, Sendable {
    case applied(Work, inverse: ComicOperation)
    /// The operation would break these two-Page Panels; apply `.confirmed(op)` to split each into one Panel per Page.
    case requiresConfirmation(splitting: [UUID])
}

public enum EditError: Error, Equatable, Sendable {
    case notFound(UUID)
    case invalid(String)
    case invariantViolated(String)
}

public protocol ComicEditing: Sendable {
    func apply(_ op: ComicOperation, to work: Work) throws -> EditResult
    func readingOrder(for chapter: Chapter, direction: ReadingDirection) -> [UUID]
    func script(for chapter: Chapter, direction: ReadingDirection) -> [Line]
    func isStale(_ render: Render, in work: Work) -> Bool
    func inputsHash(panelIDs: [UUID], in work: Work) -> String
}

public struct ComicEditor: ComicEditing {
    let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

    /// Applies `op` atomically: the result satisfies every invariant, or the call throws and nothing changes.
    // ponytail: the inverse is a snapshot of the previous Work (cheap: copy-on-write arrays). Switch to per-op
    // inverses if undo must merge with concurrent iCloud edits instead of replacing them.
    public func apply(_ op: ComicOperation, to work: Work) throws -> EditResult {
        if case .restore(let previous) = op {
            try Invariants.validate(previous)
            return .applied(previous, inverse: .restore(work))
        }
        var edit = Edit(work: work, now: now(), confirmed: false)
        if let splitting = try edit.run(op) { return .requiresConfirmation(splitting: splitting) }
        edit.work.updatedAt = edit.now
        try Invariants.validate(edit.work)
        return .applied(edit.work, inverse: .restore(work))
    }

    public func readingOrder(for chapter: Chapter, direction: ReadingDirection) -> [UUID] {
        ReadingOrder.panels(of: chapter, direction: direction)
    }

    /// All Lines of the Chapter: Panels by reading index, Bubbles by geometry in reading direction.
    public func script(for chapter: Chapter, direction: ReadingDirection) -> [Line] {
        chapter.panels.sorted { $0.readingIndex < $1.readingIndex }.flatMap { panel in
            let byID = Dictionary(uniqueKeysWithValues: panel.bubbles.map { ($0.id, $0) })
            let order = ReadingOrder.order(panel.bubbles.map { .init(id: $0.id, bounds: $0.shape.bounds) }, direction: direction)
            return order.compactMap { byID[$0]?.line }
        }
    }

    /// Stale when the Render's Panels are gone, no longer consecutive in its Chapter, or their content or Speakers changed.
    public func isStale(_ render: Render, in work: Work) -> Bool {
        !Invariants.renderPanelsAreConsecutive(render, in: work) || inputsHash(panelIDs: render.panelIDs, in: work) != render.inputsHash
    }

    /// Hash of everything a Render uses: its Panels (shape, Bubbles, Lines) and the Characters speaking in them.
    /// Timestamps and reading indexes are excluded so unrelated edits elsewhere don't make Renders stale.
    public func inputsHash(panelIDs: [UUID], in work: Work) -> String {
        struct Inputs: Encodable { let panels: [Panel?]; let characters: [Character] }
        let epoch = Date(timeIntervalSince1970: 0)
        let allPanels = Dictionary(uniqueKeysWithValues: work.chapters.flatMap(\.panels).map { ($0.id, $0) })
        let panels: [Panel?] = panelIDs.map { id in
            allPanels[id].map { p in
                var p = p
                p.createdAt = epoch; p.updatedAt = epoch; p.readingIndex = 0
                p.bubbles = p.bubbles.map { b in
                    var b = b
                    b.createdAt = epoch; b.updatedAt = epoch
                    b.line?.createdAt = epoch; b.line?.updatedAt = epoch
                    return b
                }
                return p
            }
        }
        let speakers = Set(panels.compactMap { $0 }.flatMap(\.bubbles).compactMap { $0.line?.speakerID })
        let characters = work.cast.characters.filter { speakers.contains($0.id) }.map { c in
            var c = c
            c.createdAt = epoch; c.updatedAt = epoch
            return c
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(Inputs(panels: panels, characters: characters))) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// One in-progress edit. Mutates `work`; returns Panel ids that need confirmation, if any.
private struct Edit {
    var work: Work
    let now: Date
    var confirmed: Bool

    var direction: ReadingDirection { work.readingDirection }

    mutating func run(_ op: ComicOperation) throws -> [UUID]? {
        switch op {
        case .restore:
            throw EditError.invalid("restore must be applied on its own")
        case .confirmed(let inner):
            confirmed = true
            return try run(inner)

        // MARK: Chapter
        case let .splitChapter(id, pageID, newID, newTitle):
            let c = try chapterIndex(id)
            guard let at = work.chapters[c].pages.firstIndex(where: { $0.id == pageID }), at > 0 else {
                throw EditError.invalid("split Page must be in the Chapter and not its first Page")
            }
            var pages = work.chapters.map(\.pages)
            let moved = Array(pages[c][at...])
            pages[c].removeSubrange(at...)
            pages.insert(moved, at: c + 1)
            var chapters = work.chapters
            chapters.insert(Chapter(id: newID, createdAt: now, title: newTitle, index: 0), at: c + 1)
            return try relayout(chapters: chapters, pages: pages, touched: [id, newID])
        case let .mergeChapterWithNext(id):
            let c = try chapterIndex(id)
            guard c + 1 < work.chapters.count else { throw EditError.invalid("no next Chapter") }
            var pages = work.chapters.map(\.pages)
            pages[c] += pages.remove(at: c + 1)
            var chapters = work.chapters
            chapters[c].panels += chapters.remove(at: c + 1).panels
            return try relayout(chapters: chapters, pages: pages, touched: [id])
        case let .renameChapter(id, title):
            try updateChapter(id) { $0.title = title }
        case let .setStorySummary(id, summary):
            try updateChapter(id) { $0.storySummary = summary }
        case let .moveChapter(id, toIndex):
            let c = try chapterIndex(id)
            guard work.chapters.indices.contains(toIndex) else { throw EditError.invalid("Chapter index out of range") }
            work.chapters.insert(work.chapters.remove(at: c), at: toIndex)
            for i in work.chapters.indices { work.chapters[i].index = i }

        // MARK: Page
        case let .movePage(id, toChapter, atIndex):
            let (c, p) = try pageIndex(id)
            let target = try chapterIndex(toChapter)
            var pages = work.chapters.map(\.pages)
            let page = pages[c].remove(at: p)
            guard (0...pages[target].count).contains(atIndex) else { throw EditError.invalid("Page index out of range") }
            pages[target].insert(page, at: atIndex)
            return try relayout(chapters: work.chapters, pages: pages, touched: [work.chapters[c].id, toChapter])
        case let .splitPage(id, cut, first, second):
            try splitPage(id, cut: cut, newIDs: [first, second])

        // MARK: Panel
        case let .addPanel(panel, chapterID):
            let c = try chapterIndex(chapterID)
            var ordered = work.chapters[c].panels
            ordered.insert(panel, at: max(0, min(panel.readingIndex, ordered.count)))
            work.chapters[c].panels = ordered
            renumber(c)
        case let .deletePanel(id):
            let (c, p) = try panelIndex(id)
            work.chapters[c].panels.remove(at: p)
            renumber(c)
        case let .reshapePanel(id, shape):
            try updatePanel(id) { $0.shape = shape }
        case let .splitPanel(id, from, to, newID):
            try splitPanel(id, from: from, to: to, newID: newID)
        case let .mergePanels(a, b):
            try mergePanels(a, b)
        case let .movePanel(id, toReadingIndex):
            let (c, p) = try panelIndex(id)
            guard work.chapters[c].panels.indices.contains(toReadingIndex) else { throw EditError.invalid("reading index out of range") }
            var panel = work.chapters[c].panels.remove(at: p)
            panel.readingOrderSource = .user
            work.chapters[c].panels.insert(panel, at: toReadingIndex)
            renumber(c)
        case let .recomputeReadingOrder(chapterID):
            let c = try chapterIndex(chapterID)
            let panels = work.chapters[c].panels
            let byID = Dictionary(uniqueKeysWithValues: panels.map { ($0.id, $0) })
            // Detected Panels follow geometry; user-moved Panels go back to their index, in index order.
            // ponytail: pins hold an absolute index, so deleting earlier Panels shifts what a pin follows.
            // Upgrade to "comes after Panel X" constraints if that bites.
            var ordered = ReadingOrder.panels(of: work.chapters[c], direction: direction)
                .compactMap { byID[$0] }.filter { $0.readingOrderSource == .detected }
            for pinned in panels.filter({ $0.readingOrderSource == .user }) {
                ordered.insert(pinned, at: min(pinned.readingIndex, ordered.count))
            }
            work.chapters[c].panels = ordered
            renumber(c)

        // MARK: Bubble
        case let .addBubble(bubble, panelID):
            try updatePanel(panelID) { $0.bubbles.append(bubble) }
        case let .deleteBubble(id):
            let (c, p, b) = try bubbleIndex(id)
            work.chapters[c].panels[p].bubbles.remove(at: b)
            work.chapters[c].panels[p].updatedAt = now
        case let .reshapeBubble(id, shape):
            try updateBubble(id) { $0.shape = shape }
        case let .setTextOrientation(id, orientation):
            try updateBubble(id) { $0.textOrientation = orientation; $0.orientationSource = .user }

        // MARK: Line
        case let .setLine(id, line):
            try updateBubble(id) { $0.line = line }
        case let .editSourceText(id, text):
            try updateLine(id) { $0.sourceText = text; $0.ocrSource = .user }
        case let .editTranslation(id, text):
            try updateLine(id) { $0.translation = text; $0.translationSource = .user }
        case let .setSpeaker(id, speaker):
            try updateLine(id) { $0.speakerID = speaker; $0.speakerSource = .user }

        // MARK: Cast
        case let .addCharacter(character):
            work.cast.characters.append(character)
        case let .updateCharacter(character):
            guard let i = work.cast.characters.firstIndex(where: { $0.id == character.id }) else { throw EditError.notFound(character.id) }
            work.cast.characters[i] = character
            work.cast.characters[i].updatedAt = now
        case let .deleteCharacter(id):
            guard let i = work.cast.characters.firstIndex(where: { $0.id == id }) else { throw EditError.notFound(id) }
            work.cast.characters.remove(at: i)
            let now = self.now
            forEachLine { line in
                if line.speakerID == id { line.speakerID = nil; line.updatedAt = now }
            }

        // MARK: Render
        case let .addRender(render):
            guard Invariants.renderPanelsAreConsecutive(render, in: work) else {
                throw EditError.invalid("a Render needs 1–10 consecutive Panels of one Chapter")
            }
            work.renders.append(render)
        }
        return nil
    }

    // MARK: Structural Page changes

    /// Rebuilds Chapters from new Page lists: Panels follow their Pages, two-Page Panels whose Pages are no longer
    /// adjacent are split (after confirmation), and reading order keeps Page order then previous order.
    mutating func relayout(chapters: [Chapter], pages: [[Page]], touched: Set<UUID>) throws -> [UUID]? {
        var chapterOfPage: [UUID: Int] = [:]
        var position: [UUID: Int] = [:]
        for (c, list) in pages.enumerated() {
            for (i, page) in list.enumerated() { chapterOfPage[page.id] = c; position[page.id] = i }
        }
        let allPanels = chapters.flatMap { $0.panels.sorted { $0.readingIndex < $1.readingIndex } }
        let broken = allPanels.filter { panel in
            guard panel.pageIDs.count == 2 else { return false }
            let (a, b) = (panel.pageIDs[0], panel.pageIDs[1])
            return chapterOfPage[a] != chapterOfPage[b] || position[b] != position[a]! + 1
        }
        if !broken.isEmpty && !confirmed { return broken.map(\.id) }

        let brokenIDs = Set(broken.map(\.id))
        let panels = allPanels.flatMap { brokenIDs.contains($0.id) ? splitPerPage($0) : [$0] }

        var result = chapters
        for c in result.indices {
            result[c].index = c
            result[c].pages = pages[c].enumerated().map { var p = $1; p.index = $0; return p }
            result[c].panels = []
            if touched.contains(result[c].id) { result[c].updatedAt = now }
        }
        // Stable: Panels keep their previous relative order within a Page.
        let ordered = panels.enumerated().sorted { a, b in
            (position[a.element.pageIDs[0]]!, a.offset) < (position[b.element.pageIDs[0]]!, b.offset)
        }
        for (_, panel) in ordered { result[chapterOfPage[panel.pageIDs[0]]!].panels.append(panel) }
        work.chapters = result
        for c in work.chapters.indices { renumber(c) }
        return nil
    }

    /// Splits a two-Page Panel into one Panel per Page; the first Page's piece keeps the id.
    func splitPerPage(_ panel: Panel) -> [Panel] {
        let regions = [0, 1].map { Canvas.region(slot: $0, direction: direction) }
        var pieces: [Panel] = []
        for (slot, region) in regions.enumerated() {
            let shape = panel.shape.clipped(to: region).map(region.toLocal)
            guard shape.isWellFormed else { continue }
            var piece = panel
            piece.id = slot == 0 ? panel.id : derivedID(panel.id, "page-split")
            piece.pageIDs = [panel.pageIDs[slot]]
            piece.shape = shape
            piece.updatedAt = now
            piece.bubbles = panel.bubbles.compactMap { bubble in
                let areas = regions.map { bubble.shape.clipped(to: $0).area }
                guard (areas[slot] > areas[1 - slot]) || (areas[slot] == areas[1 - slot] && slot == 0) else { return nil }
                var b = bubble
                b.shape = bubble.shape.clipped(to: region).map(region.toLocal)
                return b
            }
            pieces.append(piece)
        }
        if pieces.count == 1 { pieces[0].id = panel.id }
        return pieces
    }

    mutating func splitPage(_ id: UUID, cut: Cut, newIDs: [UUID]) throws {
        let (c, p) = try pageIndex(id)
        let page = work.chapters[c].pages[p]
        guard newIDs.count == 2, newIDs[0] != newIDs[1], !newIDs.contains(id) else {
            throw EditError.invalid("splitting a Page needs two new Page ids")
        }
        let at: Double
        let halves: [Rect]
        // Whether the halves sit in a two-Page canvas the same way they sat on the Page.
        let canvasMatchesCut: Bool
        switch cut {
        case .vertical(let x):
            at = x
            let left = Rect(minX: 0, minY: 0, maxX: x, maxY: 1), right = Rect(minX: x, minY: 0, maxX: 1, maxY: 1)
            halves = direction == .rightToLeft ? [right, left] : [left, right]
            canvasMatchesCut = direction != .verticalScroll
        case .horizontal(let y):
            at = y
            halves = [Rect(minX: 0, minY: 0, maxX: 1, maxY: y), Rect(minX: 0, minY: y, maxX: 1, maxY: 1)]
            canvasMatchesCut = direction == .verticalScroll
        }
        guard at > 0.01 && at < 0.99 else { throw EditError.invalid("cut must lie inside the Page") }

        let newPages = halves.enumerated().map { i, half in
            var part = page
            part.id = newIDs[i]
            part.createdAt = now
            part.updatedAt = now
            part.origin = .split(from: page.id, crop: page.crop.sub(half))
            part.pixelSize = PixelSize(width: Int((Double(page.pixelSize.width) * half.width).rounded()),
                                       height: Int((Double(page.pixelSize.height) * half.height).rounded()))
            return part
        }
        let eps = 1e-9
        for i in work.chapters[c].panels.indices where work.chapters[c].panels[i].pageIDs.contains(id) {
            var panel = work.chapters[c].panels[i]
            guard panel.pageIDs.count == 1 else {
                throw EditError.invalid("split the two-Page Panel \(panel.id) before splitting its Page")
            }
            if let h = halves.firstIndex(where: { half in
                panel.shape.points.allSatisfy { $0.x >= half.minX - eps && $0.x <= half.maxX + eps && $0.y >= half.minY - eps && $0.y <= half.maxY + eps }
            }) {
                panel.pageIDs = [newPages[h].id]
                panel.shape = panel.shape.map(halves[h].toLocal)
                panel.bubbles = panel.bubbles.map { var b = $0; b.shape = b.shape.clipped(to: halves[h]).map(halves[h].toLocal); return b }
            } else if canvasMatchesCut {
                // A Panel across the gutter of a two-pages-in-one scan becomes a two-Page Panel.
                func toCanvas(_ polygon: Polygon) -> Polygon {
                    Polygon.hull(halves.indices.flatMap { h in
                        polygon.clipped(to: halves[h]).map(halves[h].toLocal)
                            .map(Canvas.region(slot: h, direction: direction).fromLocal).points
                    })
                }
                panel.pageIDs = newPages.map(\.id)
                panel.shape = toCanvas(panel.shape)
                panel.bubbles = panel.bubbles.map { var b = $0; b.shape = toCanvas(b.shape); return b }
            } else {
                throw EditError.invalid("Panel \(panel.id) crosses a cut that does not match the reading direction")
            }
            panel.updatedAt = now
            work.chapters[c].panels[i] = panel
        }
        var pages = work.chapters.map(\.pages)
        pages[c].replaceSubrange(p...p, with: newPages)
        _ = try relayout(chapters: work.chapters, pages: pages, touched: [work.chapters[c].id])
    }

    // MARK: Panel geometry

    mutating func splitPanel(_ id: UUID, from: Point, to: Point, newID: UUID) throws {
        let (c, p) = try panelIndex(id)
        let panel = work.chapters[c].panels[p]
        let left = panel.shape.clipped(keepingLeftOf: from, to), right = panel.shape.clipped(keepingLeftOf: to, from)
        guard left.isWellFormed, right.isWellFormed else { throw EditError.invalid("the line does not split Panel \(id)") }
        var first = panel, second = panel
        first.shape = left; first.updatedAt = now
        second.id = newID; second.shape = right; second.createdAt = now; second.updatedAt = now
        first.bubbles = panel.bubbles.filter { cross(from, to, $0.shape.centroid) >= 0 }
        second.bubbles = panel.bubbles.filter { cross(from, to, $0.shape.centroid) < 0 }
        work.chapters[c].panels.replaceSubrange(p...p, with: [first, second])
        renumber(c)
    }

    mutating func mergePanels(_ aID: UUID, _ bID: UUID) throws {
        guard aID != bID else { throw EditError.invalid("cannot merge a Panel with itself") }
        let (c, pa) = try panelIndex(aID)
        let (cb, pb) = try panelIndex(bID)
        guard c == cb else { throw EditError.invalid("Panels are in different Chapters") }
        let chapter = work.chapters[c]
        let a = chapter.panels[pa], b = chapter.panels[pb]
        let position = Dictionary(uniqueKeysWithValues: chapter.pages.enumerated().map { ($1.id, $0) })
        let pageIDs = Array(Set(a.pageIDs + b.pageIDs)).sorted { position[$0]! < position[$1]! }
        guard pageIDs.count == 1 || (pageIDs.count == 2 && position[pageIDs[1]]! == position[pageIDs[0]]! + 1) else {
            throw EditError.invalid("merged Panel must cover one Page or two adjacent Pages")
        }
        // Maps a polygon from a source Panel's coordinates into the merged Panel's canvas.
        func toTarget(_ polygon: Polygon, from source: Panel) -> Polygon {
            guard pageIDs.count == 2, source.pageIDs.count == 1 else { return polygon }
            let region = Canvas.region(slot: pageIDs.firstIndex(of: source.pageIDs[0])!, direction: direction)
            return polygon.map(region.fromLocal)
        }
        var merged = a
        merged.pageIDs = pageIDs
        merged.shape = Polygon.hull(toTarget(a.shape, from: a).points + toTarget(b.shape, from: b).points)
        merged.bubbles = a.bubbles.map { var x = $0; x.shape = toTarget(x.shape, from: a); return x }
            + b.bubbles.map { var x = $0; x.shape = toTarget(x.shape, from: b); return x }
        merged.updatedAt = now
        // The merged Panel takes the earlier reading position.
        work.chapters[c].panels[min(pa, pb)] = merged
        work.chapters[c].panels.remove(at: max(pa, pb))
        renumber(c)
    }

    // MARK: Helpers

    /// Sets each Panel's reading index to its position.
    mutating func renumber(_ c: Int) {
        for i in work.chapters[c].panels.indices where work.chapters[c].panels[i].readingIndex != i {
            work.chapters[c].panels[i].readingIndex = i
        }
    }

    func chapterIndex(_ id: UUID) throws -> Int {
        guard let c = work.chapters.firstIndex(where: { $0.id == id }) else { throw EditError.notFound(id) }
        return c
    }

    func pageIndex(_ id: UUID) throws -> (Int, Int) {
        for (c, ch) in work.chapters.enumerated() {
            if let p = ch.pages.firstIndex(where: { $0.id == id }) { return (c, p) }
        }
        throw EditError.notFound(id)
    }

    func panelIndex(_ id: UUID) throws -> (Int, Int) {
        for (c, ch) in work.chapters.enumerated() {
            if let p = ch.panels.firstIndex(where: { $0.id == id }) { return (c, p) }
        }
        throw EditError.notFound(id)
    }

    func bubbleIndex(_ id: UUID) throws -> (Int, Int, Int) {
        for (c, ch) in work.chapters.enumerated() {
            for (p, panel) in ch.panels.enumerated() {
                if let b = panel.bubbles.firstIndex(where: { $0.id == id }) { return (c, p, b) }
            }
        }
        throw EditError.notFound(id)
    }

    mutating func updateChapter(_ id: UUID, _ change: (inout Chapter) -> Void) throws {
        let c = try chapterIndex(id)
        change(&work.chapters[c])
        work.chapters[c].updatedAt = now
    }

    mutating func updatePanel(_ id: UUID, _ change: (inout Panel) -> Void) throws {
        let (c, p) = try panelIndex(id)
        change(&work.chapters[c].panels[p])
        work.chapters[c].panels[p].updatedAt = now
    }

    mutating func updateBubble(_ id: UUID, _ change: (inout Bubble) -> Void) throws {
        let (c, p, b) = try bubbleIndex(id)
        change(&work.chapters[c].panels[p].bubbles[b])
        work.chapters[c].panels[p].bubbles[b].updatedAt = now
    }

    mutating func updateLine(_ bubbleID: UUID, _ change: (inout Line) -> Void) throws {
        let (c, p, b) = try bubbleIndex(bubbleID)
        guard work.chapters[c].panels[p].bubbles[b].line != nil else { throw EditError.invalid("Bubble \(bubbleID) has no Line") }
        change(&work.chapters[c].panels[p].bubbles[b].line!)
        work.chapters[c].panels[p].bubbles[b].line!.updatedAt = now
    }

    mutating func forEachLine(_ change: (inout Line) -> Void) {
        for c in work.chapters.indices {
            for p in work.chapters[c].panels.indices {
                for b in work.chapters[c].panels[p].bubbles.indices where work.chapters[c].panels[p].bubbles[b].line != nil {
                    change(&work.chapters[c].panels[p].bubbles[b].line!)
                }
            }
        }
    }
}

/// A deterministic id derived from another, so operations stay pure functions.
func derivedID(_ id: UUID, _ salt: String) -> UUID {
    let bytes = Array(SHA256.hash(data: Data((id.uuidString + salt).utf8)))
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], (bytes[6] & 0x0F) | 0x50, bytes[7],
                       (bytes[8] & 0x3F) | 0x80, bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
}
