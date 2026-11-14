# R1 · Panel Detection

_Package: `PanelDetection` · Tier 2 · Depends on: Comic Structure_

## Purpose
Propose Panels for each Page, on the device and free. The Panel editor (in App Shell, using Comic Structure operations) is the safety net.

## Requirements
1. **On device only.** No network calls.
2. **Heuristic first (R1):** gutter detection on a binarized Page (find light separating bands, recursive cuts), plus contour detection (Vision / Core Image) for bordered Panels. Output convex polygons, so slanted Panels are supported.
3. **Reading order** is produced by Comic Structure from the polygons and the Work's reading direction.
4. **Full-bleed Pages:** if no Panels are found, the whole Page becomes one Panel.
5. **Two-Page Panels:** when both Pages of an adjacent pair are full-bleed and their touching edges continue the same artwork (edge similarity above a threshold), propose one two-Page Panel; the user confirms with one tap.
6. **Confidence** per Panel (0–1). Low-confidence Pages are flagged in the editor ("check Panels").
7. **Performance:** ≤300 ms per Page on an iPhone 12-class device; runs in the background after import.
8. **Later (not R1):** a Core ML detector trained only on data we have rights to. Manga109 is non-commercial and must not be used.

## Public interface (sketch)
```swift
public protocol PanelDetecting {
  func detectPanels(in page: PageImage) async throws -> [PanelProposal]          // polygon + confidence
  func proposeSpread(left: PageImage, right: PageImage) async -> SpreadProposal?
}
```

## Acceptance tests (golden set)
- ≥70% of ground-truth Panels matched with IoU ≥ 0.8 before any manual edit; ≥90% of bordered Panels.
- Full-bleed fixture yields one Panel per Page.
- Two-Page spread fixture yields a spread proposal; non-spread adjacent full-bleed Pages do not.
- Performance budget met on a physical iPhone 12-class device.
- No network access (test with networking disabled at the process level).
