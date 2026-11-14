# R1 · Comic Structure (shared model)

_Package: `ComicStructure` · Tier 1 · Owner: Lead · Depends on: none_

## Purpose
The single source of truth for the domain model and the edit operations on it. Every other module uses these types. Only the Lead changes this package.

## Model

All entities have a stable `UUID` id and `createdAt`/`updatedAt`. Value types where practical; persistence mapping lives in `Persistence`.

| Type | Key fields |
|---|---|
| `Work` | `kind: WorkKind (.comic, .book)`, `title`, `readingDirection: ReadingDirection (.rightToLeft, .leftToRight, .verticalScroll)`, `sourceLanguage`, `targetLanguage`, `sources: [Source]`, `chapters: [Chapter]` (comics), `cast: Cast` |
| `Source` | `fileName`, `contentType`, `byteSize`, `fileRef` (opaque, resolved by Persistence) |
| `Chapter` | `title`, `index`, `pages: [Page]`, `storySummary: String?` (editable, see Render Client) |
| `Page` | `imageRef`, `pixelSize`, `index`, `origin: PageOrigin` (from Source entry, or split from another Page) |
| `Panel` | `pageIDs: [Page.ID]` (1 or 2, adjacent), `shape: PanelShape` (convex polygon in normalized coordinates of a virtual canvas spanning its Pages), `readingIndex`, `bubbles: [Bubble]` |
| `Bubble` | `shape`, `textOrientation: TextOrientation (.horizontal, .vertical)`, `orientationSource (.detected, .user)`, `line: Line?` |
| `Line` | `sourceText`, `translation`, `ocrSource (.onDevice, .cloud, .user)`, `translationSource (.onDevice, .user)`, `speakerID: Character.ID?`, `speakerSource (.proposed, .user)`, `furigana: [RubySpan]` |
| `Script` | derived: all Lines of a Chapter in reading order |
| `Character` | `name`, `referenceCrops: [ImageRef]` (≥1), `voiceDescription` |
| `Cast` | `characters: [Character]` |
| `Render` | `chapterID`, `panelIDs: [Panel.ID]` (1–10, consecutive in reading order), `status (.queued, .running, .ready, .failed(reason), .blocked(reason))`, `videoRef?`, `deliveredResolution`, `presets`, `note`, `inputsHash` (detects stale Renders after edits), `providerID`, `createdAt` |

## Invariants (enforced by the model, tested)
1. A Panel belongs to exactly one Chapter and covers 1 or 2 Pages; if 2, they are adjacent in the Chapter's Page order.
2. Panel `readingIndex` values in a Chapter are unique and contiguous from 0.
3. A Render's Panels are 1–10, in one Chapter, consecutive by `readingIndex`.
4. A Line's Speaker, if set, is a Character in the same Work's Cast.
5. Every Bubble lies within its Panel's shape (tolerance 2%).
6. Deleting a Character clears it as Speaker on all Lines (with undo).

## Edit operations
All operations are pure functions `(state, op) -> (state, inverse)` so undo/redo is free and testable.

- **Chapter:** split at Page; merge with next Chapter; rename; reorder.
- **Page:** split (vertical or horizontal cut, e.g. a two-pages-in-one scan); reorder within a Chapter; move to another Chapter. **No Page merge.**
- **Panel:** add, delete, reshape, split (by a line), merge (two Panels on the same or adjacent Pages, result must satisfy invariant 1), reorder reading position.
- **Moving a Page** that breaks a two-Page Panel's adjacency returns `.requiresConfirmation(splitting: [Panel.ID])`; on confirmation, each affected Panel is split into one Panel per Page.
- **Bubble:** add, delete, reshape, set orientation (marks `orientationSource = .user`).
- **Line:** edit source text, edit translation, set Speaker.
- **Reading order:** recompute from geometry and `readingDirection` (right-to-left: top-to-bottom rows, right-to-left within a row), then user overrides are kept.

Any edit to Panels, Bubbles, Lines or Cast that a Render used changes the Render's `inputsHash` comparison, and the Render is shown as **stale** (it still plays; re-rendering is the user's choice).

## Public interface (sketch)
```swift
public protocol ComicEditing {
  func apply(_ op: ComicOperation, to work: Work) throws -> EditResult   // .applied(Work, inverse) | .requiresConfirmation(...)
  func readingOrder(for chapter: Chapter, direction: ReadingDirection) -> [Panel.ID]
  func script(for chapter: Chapter) -> [Line]
  func isStale(_ render: Render, in work: Work) -> Bool
}
```

## Acceptance tests
- Every operation round-trips: `apply(op)` then `apply(inverse)` yields an equal Work (property-based tests, 1,000 random sequences).
- Invariants 1–6 hold after every operation in those sequences.
- Golden set: reading order matches ground truth for ≥95% of Panels given ground-truth Panel shapes.
- Moving Page 15 away from Page 14 with a two-Page Panel returns `requiresConfirmation` and, when confirmed, produces two single-Page Panels.
- Model encodes/decodes to a versioned JSON schema (`schemaVersion`), with a migration test for every version bump.

## Out of scope
Persistence, file I/O, UI.
