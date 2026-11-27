# The book track comes before the comic track in R1

R1 builds the EPUB toolkit before any comic work. M2 is EPUB core, the Library, the metadata editor and metadata lookup. M3 is the content editor, and M4 is the EPUB reader with Read-aloud. Comic import and editing, Text, the Player, Cast and Renders, payments and the App Store release follow from M5, in their original order. The Lead decided this on 2026-11-25: fixing EPUB metadata on iPhone and iPad is useful on its own, needs no cloud, no paid provider and no backend, and builds pieces that the comic track reuses (the real Library screen, `Archive`, `ReadAloud`, multi-file import). The confirmed decisions are in `specs/book-track-brief.md`, and M2 is specified in GitHub issue #37.

## Consequences
- `specs/00-overview.md` §9 is renumbered: the old M2–M7 become M5–M10, with unchanged exit criteria.
- **M0 Trials gates M6, not M2.** Vertical OCR and video provider choices are needed only once Text (M6) and Renders (M8) start. M0 runs any time before M6.
- **Per-entity merge (ADR 0007) moves to before comic editing (M5).** In M2–M4 a book Work is edited as a whole `BookMetadata` replacement and its EPUB is an immutable file, so whole-Work last-writer-wins stays acceptable: a conflict loses at most one device's unsynced metadata edit, which the user can redo.
- **Platforms for M2–M4:** iPhone and iPad only. Code editing (M3) is iPad only, as R5 says. No Mac target yet.
- The phases R1.5 (Metadata Editor Lite), part of R3 (web lookup), part of R5 (content editor) and part of R2 (reader and Read-aloud) are pulled into R1 as M2–M4. Their phase specs stay as the behavioural source. What each milestone takes from them is in the brief.
