# R1 · Player

_Package: `Player` · Tier 2 · Depends on: Comic Structure, Text, Read-aloud, Render Client_

## Purpose
The in-app viewer that steps through a Chapter's Panels in reading order, playing each Panel's Render or its Read-aloud. It merges the old "Manga Reader" and "Manga Motion" ideas.

## Views
- **Panel view (default):** one Panel at a time, zoomed to fill the screen like a page; two-Page Panels are shown as one image. Swipe or tap to advance in reading order; direction follows the Work's reading direction.
- **Page view:** whole Page, with Panel outlines on demand; tap a Panel to jump into Panel view.

## Behaviour
1. For each Panel in order:
   - If a **ready Render** covers it, play the Render (one Render can cover 1–10 Panels; the Player plays it once across those Panels, then continues after the last one). Stale Renders play with a small "edited since render" badge.
   - Otherwise **Read-aloud** speaks its Lines (Story or Learn mode).
   - A Render in progress shows "Rendering…"; Read-aloud performs the Panel meanwhile.
2. **Subtitles:** Story mode — translation. Learn mode — two lines: source text with furigana, translation below; can hide either line ("quiz" toggle per Line by tap).
3. **Autoplay** (advance after Read-aloud or Render ends) or manual.
4. Vertical Bubbles without text (not entitled) show "vertical text: unlock to read" and are skipped by Read-aloud.
5. **Render button** opens the Render selection starting at the current Panel.
6. **Watermark:** not applicable (free users cannot make Renders). Renders cannot be exported or shared; no share sheet, AirDrop or Save to Photos; screenshots are not blocked.
7. Remembers reading position per Chapter, synced via iCloud.

## Acceptance tests
- Reading order matches Comic Structure for right-to-left and left-to-right Works.
- A Render covering Panels 3–6 plays once and the Player resumes at Panel 7.
- Learn-mode subtitles show furigana aligned over kanji; quiz toggle hides and reveals.
- No path in the UI exports or shares a Render file (UI test enumerates share entry points).
- 60 fps Panel transitions on iPhone 12-class devices.
