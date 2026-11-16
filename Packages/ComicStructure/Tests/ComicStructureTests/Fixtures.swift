import Foundation
@testable import ComicStructure

let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
let editor = ComicEditor(now: { fixedDate })

func rect(_ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) -> Polygon {
    .rect(Rect(minX: minX, minY: minY, maxX: maxX, maxY: maxY))
}

func makePage(_ index: Int) -> Page {
    Page(createdAt: fixedDate, imageRef: FileRef("page/\(index)"), pixelSize: PixelSize(width: 1000, height: 1400),
         index: index, origin: .sourceEntry("\(index).png"))
}

/// A right-to-left comic: Chapter 0 has 20 Pages with two single-Page Panels each, except that Pages 14 and 15
/// share one two-Page Panel. Chapter 1 has 3 Pages. One Character speaks one Line.
func makeWork() -> Work {
    let hero = Character(createdAt: fixedDate, name: "Hero", referenceCrops: [FileRef("crop/hero")])
    var pages0 = (0..<20).map(makePage)
    var panels: [Panel] = []
    for page in pages0 where page.index != 14 && page.index != 15 {
        panels.append(Panel(createdAt: fixedDate, pageIDs: [page.id], shape: rect(0.5, 0, 1, 0.5), readingIndex: 0))
        panels.append(Panel(createdAt: fixedDate, pageIDs: [page.id], shape: rect(0, 0, 0.5, 0.5), readingIndex: 0))
        if page.index == 13 { break }
    }
    let line = Line(createdAt: fixedDate, sourceText: "行くぞ", translation: "Let's go", ocrSource: .onDevice, speakerID: hero.id)
    let bubbleRight = Bubble(createdAt: fixedDate, shape: rect(0.7, 0.1, 0.8, 0.4), textOrientation: .vertical, line: line)
    let bubbleLeft = Bubble(createdAt: fixedDate, shape: rect(0.2, 0.1, 0.3, 0.4), textOrientation: .vertical)
    panels.append(Panel(createdAt: fixedDate, pageIDs: [pages0[14].id, pages0[15].id], shape: rect(0, 0, 1, 0.5),
                        readingIndex: 0, bubbles: [bubbleRight, bubbleLeft]))
    for page in pages0[16...] {
        panels.append(Panel(createdAt: fixedDate, pageIDs: [page.id], shape: rect(0, 0, 1, 1), readingIndex: 0))
    }
    for i in panels.indices { panels[i].readingIndex = i }
    pages0 = pages0.enumerated().map { var p = $1; p.index = $0; return p }
    let ch0 = Chapter(createdAt: fixedDate, title: "One", index: 0, pages: pages0, panels: panels)
    let ch1 = Chapter(createdAt: fixedDate, title: "Two", index: 1, pages: (0..<3).map(makePage))
    return Work(createdAt: fixedDate, kind: .comic, title: "Test", readingDirection: .rightToLeft,
                chapters: [ch0, ch1], cast: Cast(characters: [hero]))
}

extension EditResult {
    var work: Work? { if case .applied(let w, _) = self { return w } else { return nil } }
    var inverse: ComicOperation? { if case .applied(_, let inv) = self { return inv } else { return nil } }
}
