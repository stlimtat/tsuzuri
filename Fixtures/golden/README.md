# Golden test set

Shared fixtures owned by the Lead and used by every module (specs/00-overview.md §8). Only openly licensed or self-drawn material; **no commercial manga**.

| Path | Contents | Used by |
|---|---|---|
| `ground-truth/reading-order.json` | Panel polygons per Page, listed in reading order | `ComicStructure` reading-order test (≥95% of Panels must match) |
| `generate.swift` | Deterministic generator: draws every generated Page and writes its ground truth, `manifest.json` and `LICENSES.md` from one layout description (`swift Fixtures/golden/generate.swift`) | Lead, when adding Pages |
| `pages/<id>.png` | Generated Page images (greyscale; 800×1200, or 1200×900 for a two-pages-in-one scan) | Every module |
| `ground-truth/pages/<id>.json` | Per Page: pixel size, reading direction, Panels (polygon, reading index) and their Bubbles (polygon, text orientation, Line text, furigana, SFX flag, poisoned flag); for a two-pages-in-one scan, its `expectedCut` (`{"x": …}` for a vertical cut) | `ComicStructure` golden set tests, OCR, Panel detection |
| `ground-truth/spreads/<id>.json` | Two adjacent Pages (ids in Page order) and their two-Page Panels, each one convex polygon in the canvas spanning both Pages, as `ComicStructure` stores it | Same |
| `manifest.json` | Features of each generated Page: `verticalText`, `horizontalText`, `borderlessPanel`, `slantedPanel`, `twoPagePanel`, `twoPagesInOneScan`, `sfx`, `furigana`, `smallFurigana` (furigana on text of 16 px or less), `denseDialogue` (8+ dialogue Bubbles), `poisonedText` | Coverage checks |
| `LICENSES.md` | Licence of each Page (all self-drawn so far) | Licence check |
| `poisoned/notes.json` | Prompt-injection strings for notes, Cast fields, summaries and Panel text | Security red-team suite, Render Client, Backend |

## Status (M1)

- Reading-order ground truth: 15 synthetic layouts (right-to-left, left-to-right, vertical scroll; slanted gutters, borderless, inset, tall and L-shaped arrangements).
- Generated Pages (#4, #11): 32 self-drawn Pages from `generate.swift` (two spreads, three two-pages-in-one scans), 111 Panels, every §8 feature on at least two Pages: vertical and horizontal text, borderless and slanted Panels, two-Page Panels, two-pages-in-one scans with their expected cut, SFX, small furigana, dense dialogue and poisoned text (prompt injection in Bubbles, in Japanese and English, flagged `poisoned`). Right-to-left, left-to-right and vertical-scroll Pages.
- Validated in CI by `GoldenSetTests`: pairing of images, ground truth, manifest and licences; `schemaVersion`; coordinates in 0…1; convex Panels; Bubbles within their Panel by 2%; spreads referencing real Pages; each §8 feature on at least two Pages; manifest agreeing with the ground truth on poisoned text and scans. The reading-order test (≥95%) reads every Page, each scan after cutting it at its expected cut with `splitPage`.
- Openly licensed real-comic Pages can be added later in the same format.

## Rules

- Coordinates are normalized to the Page (0…1, origin top-left).
- Every file carries `schemaVersion`.
- Generated Pages are never edited by hand: change `generate.swift` and re-run it. CI validates the committed output; it doesn't regenerate. Output is byte-identical when re-run on the same macOS version.
- Reading indexes count within a Page, across the whole spread for a spread's Pages and its two-Page Panels, and across the whole scan for a two-pages-in-one scan. A scan's Panels lie on either side of its expected cut.
- A Bubble's polygon is the rect its balloon is drawn in. The generator stops if a Bubble's text doesn't fit its balloon, so ground truth holds exactly the text drawn. Furigana `start` and `length` count Characters of the Line text.
- Changing an expected value needs Lead review: it changes every module's definition of done.
