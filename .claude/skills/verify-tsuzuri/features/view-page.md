# View a Work's Page

Tapping a Work opens a sheet showing its first Page image. `Done` closes it and returns to the unchanged Library.

## Sub-features

- `view-open` opens the sheet with the Page image (`pageImage`) at a non-zero size.
- `view-done` closes the sheet with `Done` and leaves the row in place.

## How to get to it (user POV)

- Tap a Work row in the Library.

## Driving it with verify-tsuzuri

Preconditions:

- Baseline from the README, plus one Work added through [Add a sample Work](./add-sample-work.md).

- **Open.** Tap the middle of the `Sample Work` row (about (200, 280) pt on iPhone 17 with the banner showing). A sheet slides up showing the golden Page `p01-vertical-grid` (a manga page with vertical text), with `Done` at the top right. Run `$V screenshot 03-page-sheet`.
- **Close.** Tap `Done`. The sheet goes away and the `Sample Work` row is still listed. Run `$V screenshot 04-after-done`.
- **No side effect.** Run `$V library 04-after-done`. The record is unchanged from before the tap (same `updatedAt`).
- **Stable-handle check.** Run `$V ui-test testTappingAWorkShowsItsPageUntilDone`. The summary reports 1 passed.

## Gotchas

- A long press opens the context menu instead of the sheet. Keep taps short.
- Swiping the sheet down also closes it. That path is not mapped as a separate entry point yet.
