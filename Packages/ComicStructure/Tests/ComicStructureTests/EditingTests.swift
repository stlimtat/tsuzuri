import Foundation
import Testing
@testable import ComicStructure

@Suite struct EditingTests {
    let work = makeWork()

    @Test func fixtureSatisfiesInvariants() throws {
        try Invariants.validate(work)
    }

    @Test func movingPage15AwayFromPage14RequiresConfirmationThenSplitsThePanel() throws {
        let ch = work.chapters[0]
        let p15 = ch.pages[15].id
        let twoPage = try #require(ch.panels.first { $0.pageIDs.count == 2 })
        let op = ComicOperation.movePage(p15, toChapter: ch.id, atIndex: 18)

        #expect(try editor.apply(op, to: work) == .requiresConfirmation(splitting: [twoPage.id]))

        let result = try #require(try editor.apply(.confirmed(op), to: work).work)
        let pieces = result.chapters[0].panels.filter { $0.id == twoPage.id || $0.pageIDs == [p15] && $0.bubbles.count == 1 }
        #expect(pieces.count == 2)
        #expect(Set(pieces.flatMap(\.pageIDs)) == [ch.pages[14].id, p15])
        #expect(pieces.allSatisfy { $0.pageIDs.count == 1 && $0.bubbles.count == 1 })
        // The right half of a right-to-left spread is the first Page (14); its bubble keeps the Line.
        let onP14 = try #require(pieces.first { $0.pageIDs == [ch.pages[14].id] })
        #expect(onP14.bubbles[0].line?.sourceText == "行くぞ")
        #expect(onP14.shape.bounds == Rect(minX: 0, minY: 0, maxX: 1, maxY: 0.5))
        try Invariants.validate(result)
    }

    @Test func undoRestoresTheOriginalWork() throws {
        let op = ComicOperation.renameChapter(work.chapters[0].id, title: "Renamed")
        let result = try editor.apply(op, to: work)
        let renamed = try #require(result.work)
        #expect(renamed.chapters[0].title == "Renamed")
        let inverse = try #require(result.inverse)
        let undone = try #require(try editor.apply(inverse, to: renamed).work)
        #expect(undone == work)
    }

    @Test func deletingACharacterClearsItAsSpeakerAndUndoRestoresIt() throws {
        let hero = work.cast.characters[0]
        let result = try editor.apply(.deleteCharacter(hero.id), to: work)
        let edited = try #require(result.work)
        #expect(edited.cast.characters.isEmpty)
        #expect(editor.script(for: edited.chapters[0], direction: .rightToLeft).allSatisfy { $0.speakerID == nil })
        let inverse = try #require(result.inverse)
        let undone = try #require(try editor.apply(inverse, to: edited).work)
        #expect(editor.script(for: undone.chapters[0], direction: .rightToLeft).first?.speakerID == hero.id)
    }

    @Test func settingASpeakerOutsideTheCastIsRejected() throws {
        let bubble = work.chapters[0].panels.flatMap(\.bubbles)[0]
        #expect(throws: EditError.self) { try editor.apply(.setSpeaker(bubbleID: bubble.id, UUID()), to: work) }
    }

    @Test func reshapingAPanelAwayFromItsBubblesIsRejected() throws {
        let panel = try #require(work.chapters[0].panels.first { !$0.bubbles.isEmpty })
        #expect(throws: EditError.self) { try editor.apply(.reshapePanel(panel.id, rect(0, 0.6, 1, 1)), to: work) }
    }

    @Test func splitAndMergePanelOnOnePage() throws {
        let panel = work.chapters[0].panels[0]
        let newID = UUID()
        let split = try #require(try editor.apply(.splitPanel(panel.id, from: Point(0.75, 1), to: Point(0.75, 0), newPanelID: newID), to: work).work)
        let pieces = split.chapters[0].panels.filter { [panel.id, newID].contains($0.id) }
        #expect(pieces.count == 2)
        #expect(abs(pieces.map(\.shape.area).reduce(0, +) - panel.shape.area) < 1e-9)
        #expect(split.chapters[0].panels[1].id == newID, "new piece follows the original in reading order")

        let merged = try #require(try editor.apply(.mergePanels(panel.id, newID), to: split).work)
        let back = try #require(merged.chapters[0].panels.first { $0.id == panel.id })
        #expect(back.shape.bounds == panel.shape.bounds)
        #expect(merged.chapters[0].panels.count == work.chapters[0].panels.count)
    }

    @Test func mergingPanelsOnAdjacentPagesMakesATwoPagePanel() throws {
        let ch = work.chapters[0]
        let a = try #require(ch.panels.first { $0.pageIDs == [ch.pages[16].id] })
        let b = try #require(ch.panels.first { $0.pageIDs == [ch.pages[17].id] })
        let merged = try #require(try editor.apply(.mergePanels(a.id, b.id), to: work).work)
        let panel = try #require(merged.chapters[0].panels.first { $0.id == a.id })
        #expect(panel.pageIDs == [ch.pages[16].id, ch.pages[17].id])
        #expect(panel.shape.bounds == .unit)
    }

    @Test func mergingPanelsOnNonAdjacentPagesIsRejected() throws {
        let ch = work.chapters[0]
        let a = try #require(ch.panels.first { $0.pageIDs == [ch.pages[16].id] })
        let c = try #require(ch.panels.first { $0.pageIDs == [ch.pages[18].id] })
        #expect(throws: EditError.self) { try editor.apply(.mergePanels(a.id, c.id), to: work) }
    }

    @Test func splittingATwoPagesInOneScanKeepsRightHalfFirstForRightToLeft() throws {
        let ch = work.chapters[1]
        let page = ch.pages[1]
        let (a, b) = (UUID(), UUID())
        let result = try #require(try editor.apply(.splitPage(page.id, cut: .vertical(x: 0.5), firstPageID: a, secondPageID: b), to: work).work)
        let pages = result.chapters[1].pages
        #expect(pages.map(\.id) == [ch.pages[0].id, a, b, ch.pages[2].id])
        #expect(pages[1].origin == .split(from: page.id, crop: Rect(minX: 0.5, minY: 0, maxX: 1, maxY: 1)))
        #expect(pages[2].crop == Rect(minX: 0, minY: 0, maxX: 0.5, maxY: 1))
        #expect(pages[1].pixelSize == PixelSize(width: 500, height: 1400))
        #expect(pages.map(\.index) == [0, 1, 2, 3])
    }

    @Test func splittingAPageMovesItsPanelsToTheRightHalf() throws {
        let ch = work.chapters[0]
        let page = ch.pages[0]
        let (a, b) = (UUID(), UUID())
        let result = try #require(try editor.apply(.splitPage(page.id, cut: .vertical(x: 0.5), firstPageID: a, secondPageID: b), to: work).work)
        let panels = result.chapters[0].panels.prefix(2)
        #expect(panels.map(\.pageIDs) == [[a], [b]])
        #expect(panels.allSatisfy { $0.shape.bounds == Rect(minX: 0, minY: 0, maxX: 1, maxY: 0.5) })
    }

    @Test func aPanelAcrossTheGutterOfASplitScanBecomesATwoPagePanel() throws {
        let ch = work.chapters[0]
        let page = ch.pages[16]  // one full-Page Panel
        let (a, b) = (UUID(), UUID())
        let result = try #require(try editor.apply(.splitPage(page.id, cut: .vertical(x: 0.4), firstPageID: a, secondPageID: b), to: work).work)
        let panel = try #require(result.chapters[0].panels.first { $0.pageIDs.contains(a) })
        #expect(panel.pageIDs == [a, b])
        #expect(panel.shape.bounds == .unit)
    }

    @Test func scriptFollowsTheReadingDirectionWithinAPanel() throws {
        let ch = work.chapters[0]
        let panel = try #require(ch.panels.first { $0.pageIDs.count == 2 })
        let left = try #require(panel.bubbles.first { $0.line == nil })
        let line = Line(createdAt: fixedDate, sourceText: "左", ocrSource: .onDevice)
        let edited = try #require(try editor.apply(.setLine(bubbleID: left.id, line), to: work).work)
        #expect(editor.script(for: edited.chapters[0], direction: .rightToLeft).map(\.sourceText) == ["行くぞ", "左"])
        #expect(editor.script(for: edited.chapters[0], direction: .leftToRight).map(\.sourceText) == ["左", "行くぞ"])
    }

    @Test func splitAndMergeChapters() throws {
        let ch = work.chapters[0]
        let newID = UUID()
        let split = try #require(try editor.apply(.splitChapter(ch.id, atPage: ch.pages[10].id, newChapterID: newID, newTitle: "One b"), to: work).work)
        #expect(split.chapters.map(\.id) == [ch.id, newID, work.chapters[1].id])
        #expect(split.chapters[1].pages.count == 10)
        #expect(split.chapters[1].panels.first?.readingIndex == 0)
        try Invariants.validate(split)

        let merged = try #require(try editor.apply(.mergeChapterWithNext(ch.id), to: split).work)
        #expect(merged.chapters[0].pages == ch.pages)
        #expect(merged.chapters[0].panels.map(\.id) == ch.panels.map(\.id))
    }

    @Test func splittingAChapterThroughATwoPagePanelRequiresConfirmation() throws {
        let ch = work.chapters[0]
        let op = ComicOperation.splitChapter(ch.id, atPage: ch.pages[15].id, newChapterID: UUID(), newTitle: "x")
        guard case .requiresConfirmation(let ids) = try editor.apply(op, to: work) else { Issue.record(); return }
        #expect(ids.count == 1)
        let confirmed = try #require(try editor.apply(.confirmed(op), to: work).work)
        try Invariants.validate(confirmed)
    }

    @Test func renderGoesStaleWhenALineItUsedChanges() throws {
        let ch = work.chapters[0]
        let panels = Array(ch.panels.filter { $0.pageIDs.count == 2 || $0.pageIDs == [ch.pages[16].id] })
        let ids = panels.map(\.id)
        let render = Render(createdAt: fixedDate, chapterID: ch.id, panelIDs: ids, inputsHash: editor.inputsHash(panelIDs: ids, in: work), providerID: "p")
        let withRender = try #require(try editor.apply(.addRender(render), to: work).work)
        #expect(!editor.isStale(render, in: withRender))

        // An unrelated edit elsewhere does not make it stale.
        let renamed = try #require(try editor.apply(.renameChapter(ch.id, title: "New"), to: withRender).work)
        #expect(!editor.isStale(render, in: renamed))

        let bubble = panels[0].bubbles[0]
        let edited = try #require(try editor.apply(.editTranslation(bubbleID: bubble.id, "Go!"), to: withRender).work)
        #expect(editor.isStale(render, in: edited))
    }

    @Test func renderOfNonConsecutivePanelsIsRejected() throws {
        let ch = work.chapters[0]
        let ids = [ch.panels[0].id, ch.panels[2].id]
        let render = Render(chapterID: ch.id, panelIDs: ids, inputsHash: editor.inputsHash(panelIDs: ids, in: work), providerID: "p")
        #expect(throws: EditError.self) { try editor.apply(.addRender(render), to: work) }
    }

    @Test func editsMarkTheEditedEntityAndWorkUpdated() throws {
        let later = Date(timeIntervalSince1970: 1_900_000_000)
        let bubble = work.chapters[0].panels.flatMap(\.bubbles)[0]
        let edited = try #require(try ComicEditor(now: { later }).apply(.editSourceText(bubbleID: bubble.id, "待て"), to: work).work)
        let line = try #require(editor.script(for: edited.chapters[0], direction: .rightToLeft).first { $0.sourceText == "待て" })
        #expect(line.updatedAt == later && line.ocrSource == .user)
        #expect(edited.updatedAt == later)
    }

    @Test func scriptIsInReadingOrder() throws {
        let script = editor.script(for: work.chapters[0], direction: .rightToLeft)
        #expect(script.map(\.sourceText) == ["行くぞ"])
    }
}
