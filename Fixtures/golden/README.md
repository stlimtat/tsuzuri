# Golden test set

Shared fixtures owned by the Lead and used by every module (specs/00-overview.md §8). Only openly licensed or self-drawn material; **no commercial manga**.

| Path | Contents | Used by |
|---|---|---|
| `ground-truth/reading-order.json` | Panel polygons per Page, listed in reading order | `ComicStructure` reading-order test (≥95% of Panels must match) |
| `poisoned/notes.json` | Prompt-injection strings for notes, Cast fields, summaries and Panel text | Security red-team suite, Render Client, Backend |

## Status (M1)

- Reading-order ground truth: 15 synthetic layouts (right-to-left, left-to-right, vertical scroll; slanted gutters, borderless, inset, tall and L-shaped arrangements).
- **Still needed (Lead):** 30+ Page images of openly licensed or self-drawn comics, each with ground truth for Panels, Bubbles, text orientation and Line text, covering vertical and horizontal text, borderless and slanted Panels, a two-Page Panel, a two-pages-in-one scan, SFX, small furigana and dense dialogue. Add them as `pages/<id>.png` + `ground-truth/pages/<id>.json` and record the licence of each in `LICENSES.md`.

## Rules

- Coordinates are normalized to the Page (0…1, origin top-left).
- Every file carries `schemaVersion`.
- Changing an expected value needs Lead review: it changes every module's definition of done.
