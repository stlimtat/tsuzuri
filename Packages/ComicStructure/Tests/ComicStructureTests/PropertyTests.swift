import Foundation
import Testing
@testable import ComicStructure

/// Deterministic RNG so failures reproduce from the printed seed.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A random operation that targets entities in `work`; it may still be rejected by the editor.
func randomOperation(in work: Work, using rng: inout SplitMix64) -> ComicOperation {
    func pick<T>(_ xs: [T]) -> T? { xs.isEmpty ? nil : xs.randomElement(using: &rng) }
    func unit() -> Double { Double.random(in: 0.05...0.95, using: &rng) }
    func box() -> Polygon {
        let x = Double.random(in: 0...0.6, using: &rng), y = Double.random(in: 0...0.6, using: &rng)
        return rect(x, y, x + Double.random(in: 0.1...0.4, using: &rng), y + Double.random(in: 0.1...0.4, using: &rng))
    }
    let chapters = work.chapters
    let pages = chapters.flatMap(\.pages)
    let panels = chapters.flatMap(\.panels)
    let bubbles = panels.flatMap(\.bubbles)
    let fallback = ComicOperation.renameChapter(chapters[0].id, title: "t\(rng.next() % 100)")
    let id = derivedID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), String(rng.next()))

    switch rng.next() % 27 {
    case 0: return pick(chapters).flatMap { c in pick(Array(c.pages.dropFirst())).map { .splitChapter(c.id, atPage: $0.id, newChapterID: id, newTitle: "s") } } ?? fallback
    case 1: return pick(chapters).map { .mergeChapterWithNext($0.id) } ?? fallback
    case 2: return pick(chapters).map { .moveChapter($0.id, toIndex: Int(rng.next() % UInt64(chapters.count))) } ?? fallback
    case 3: return pick(chapters).map { .setStorySummary($0.id, Bool.random(using: &rng) ? "summary" : nil) } ?? fallback
    case 4: return pick(pages).map { .splitPage($0.id, cut: Bool.random(using: &rng) ? .vertical(x: unit()) : .horizontal(y: unit()), firstPageID: derivedID(id, "a"), secondPageID: derivedID(id, "b")) } ?? fallback
    case 5, 6:
        guard let page = pick(pages), let target = pick(chapters) else { return fallback }
        let op = ComicOperation.movePage(page.id, toChapter: target.id, atIndex: Int(rng.next() % UInt64(target.pages.count + 1)))
        return Bool.random(using: &rng) ? .confirmed(op) : op
    case 7:
        guard let c = pick(chapters), let page = pick(c.pages) else { return fallback }
        return .addPanel(Panel(id: id, pageIDs: [page.id], shape: box(), readingIndex: Int(rng.next() % 50)), chapterID: c.id)
    case 8: return pick(panels).map { .deletePanel($0.id) } ?? fallback
    case 9: return pick(panels).map { .reshapePanel($0.id, box()) } ?? fallback
    case 10: return pick(panels).map { .splitPanel($0.id, from: Point(unit(), 0), to: Point(unit(), 1), newPanelID: id) } ?? fallback
    case 11, 12:
        guard let c = pick(chapters), let a = pick(c.panels), let b = pick(c.panels) else { return fallback }
        return .mergePanels(a.id, b.id)
    case 13: return pick(panels).map { .movePanel($0.id, toReadingIndex: Int(rng.next() % 40)) } ?? fallback
    case 14: return pick(chapters).map { .recomputeReadingOrder(chapterID: $0.id) } ?? fallback
    case 15:
        guard let panel = pick(panels) else { return fallback }
        let b = panel.shape.bounds
        let inner = rect(b.minX + b.width * 0.3, b.minY + b.height * 0.3, b.minX + b.width * 0.6, b.minY + b.height * 0.6)
        return .addBubble(Bubble(id: id, shape: inner, textOrientation: .vertical,
                                 line: Line(id: derivedID(id, "line"), sourceText: "あ", ocrSource: .onDevice)), panelID: panel.id)
    case 16: return pick(bubbles).map { .deleteBubble($0.id) } ?? fallback
    case 17: return pick(bubbles).map { .setTextOrientation(bubbleID: $0.id, Bool.random(using: &rng) ? .horizontal : .vertical) } ?? fallback
    case 18: return pick(bubbles).map { .editSourceText(bubbleID: $0.id, "テキスト\(rng.next() % 10)") } ?? fallback
    case 19: return pick(bubbles).map { .editTranslation(bubbleID: $0.id, "text \(rng.next() % 10)") } ?? fallback
    case 20: return pick(bubbles).map { .setSpeaker(bubbleID: $0.id, pick(work.cast.characters)?.id) } ?? fallback
    case 24: return pick(bubbles).map { .reshapeBubble($0.id, $0.shape.map { Point($0.x * 0.99 + 0.005, $0.y * 0.99 + 0.005) }) } ?? fallback
    case 25: return pick(bubbles).map { .setLine(bubbleID: $0.id, Bool.random(using: &rng) ? nil : Line(id: derivedID(id, "l"), sourceText: "い", ocrSource: .cloud)) } ?? fallback
    case 26: return pick(work.cast.characters).map { var c = $0; c.name = "N\(rng.next() % 9)"; return .updateCharacter(c) } ?? fallback
    case 21: return .addCharacter(Character(id: id, name: "C", referenceCrops: [FileRef("crop/c")]))
    case 22: return pick(work.cast.characters).map { .deleteCharacter($0.id) } ?? fallback
    default:
        guard let c = pick(chapters), !c.panels.isEmpty else { return fallback }
        let ordered = c.panels.sorted { $0.readingIndex < $1.readingIndex }
        let start = Int(rng.next() % UInt64(ordered.count))
        let ids = ordered[start..<min(ordered.count, start + 1 + Int(rng.next() % 10))].map(\.id)
        return .addRender(Render(id: id, chapterID: c.id, panelIDs: ids, inputsHash: editor.inputsHash(panelIDs: ids, in: work), providerID: "p"))
    }
}

@Suite struct PropertyTests {
    @Test func everyOperationRoundTripsAndKeepsInvariants() throws {
        var applied = 0
        for seed in 0..<1_000 as Range<UInt64> {
            var rng = SplitMix64(state: seed)
            var work = makeWork()
            for step in 0..<10 {
                let op = randomOperation(in: work, using: &rng)
                let result: EditResult
                do { result = try editor.apply(op, to: work) } catch is EditError { continue }
                guard case .applied(let next, let inverse) = result else { continue }
                applied += 1
                try #require(throws: Never.self, "seed \(seed) step \(step): invariants after \(op)") { try Invariants.validate(next) }
                let back = try #require(try editor.apply(inverse, to: next).work)
                #expect(back == work, "seed \(seed) step \(step): inverse of \(op) does not restore the Work")
                // Redo is the inverse of the inverse.
                let redoOp = try #require(try editor.apply(inverse, to: next).inverse)
                #expect(try editor.apply(redoOp, to: back).work == next, "seed \(seed) step \(step): redo")
                work = next
            }
        }
        #expect(applied > 3_000, "generator should mostly produce applicable operations, got \(applied)")
    }
}
