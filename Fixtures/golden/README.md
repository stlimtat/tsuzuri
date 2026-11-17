# Golden test set

Shared fixtures owned by the Lead and used by every module (specs/00-overview.md §8). Only openly licensed or self-drawn material; **no commercial manga**.

| Path | Contents | Used by |
|---|---|---|
| `ground-truth/reading-order.json` | Panel polygons per Page, listed in reading order | `ComicStructure` reading-order test (≥95% of Panels must match) |
| `generate.swift` | Deterministic generator: draws every generated Page and writes its ground truth, `manifest.json` and `LICENSES.md` from one layout description (`swift Fixtures/golden/generate.swift`) | Lead, when adding Pages |
| `pages/<id>.png` | Generated Page images (800×1200, greyscale) | Every module |
| `ground-truth/pages/<id>.json` | Per Page: pixel size, reading direction, Panels (polygon, reading index) and their Bubbles (polygon, text orientation, Line text, furigana, SFX flag, poisoned flag) | `ComicStructure` golden set tests, OCR, Panel detection |
| `ground-truth/spreads/<id>.json` | Two adjacent Pages (ids in Page order) and their two-Page Panels, each one convex polygon in the canvas spanning both Pages, as `ComicStructure` stores it | Same |
| `manifest.json` | Features of each generated Page | Coverage checks |
| `LICENSES.md` | Licence of each Page (all self-drawn so far) | Licence check |
| `poisoned/notes.json` | Prompt-injection strings for notes, Cast fields, summaries and Panel text | Security red-team suite, Render Client, Backend |

## Status (M1)

- Reading-order ground truth: 15 synthetic layouts (right-to-left, left-to-right, vertical scroll; slanted gutters, borderless, inset, tall and L-shaped arrangements).
- Generated Pages (tracer, #4): 6 self-drawn Pages from `generate.swift`, covering vertical and horizontal text, furigana, SFX, slanted and borderless Panels, poisoned text and one two-Page spread. Validated in CI by `GoldenSetTests` (pairing of images, ground truth, manifest and licences; `schemaVersion`; coordinates in 0…1; convex Panels; Bubbles within their Panel by 2%; spreads referencing real Pages) and by the reading-order test (≥95%).
- **Still needed (#11):** the full set of 30+ Page images of openly licensed or self-drawn comics, each with ground truth for Panels, Bubbles, text orientation and Line text, covering vertical and horizontal text, borderless and slanted Panels, a two-Page Panel, a two-pages-in-one scan, SFX, small furigana and dense dialogue. Add them as `pages/<id>.png` + `ground-truth/pages/<id>.json` and record the licence of each in `LICENSES.md`.

## Rules

- Coordinates are normalized to the Page (0…1, origin top-left).
- Every file carries `schemaVersion`.
- Generated Pages are never edited by hand: change `generate.swift` and re-run it. CI validates the committed output; it doesn't regenerate. Output is byte-identical when re-run on the same macOS version.
- Reading indexes count within a Page, or across the whole spread for a spread's Pages and its two-Page Panels.
- A Bubble's polygon is the rect its balloon is drawn in. Furigana `start` and `length` count Characters of the Line text.
- Changing an expected value needs Lead review: it changes every module's definition of done.
