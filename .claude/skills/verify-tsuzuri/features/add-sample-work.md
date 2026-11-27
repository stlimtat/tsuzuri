# Add a sample Work

The toolbar `+` adds a one-Page comic Work named "Sample Work" to the Library. It appears as a row with its Page count, is saved on the device, is queued for iCloud, and survives a relaunch.

## Sub-features

- `add-row` adds one row reading `Sample Work`, `Pages: 1`, `Downloaded: 1`, and hides the empty state.
- `add-record` writes one Work record and its Page image, and queues both in the outbox.
- `add-persist` keeps the Work after the app is relaunched.
- `add-offline` works while iCloud is unavailable (the banner stays).

## How to get to it (user POV)

- Tap the `+` button (Add Sample Work) at the top right of the Library.

## Driving it with verify-tsuzuri

Preconditions:

- Baseline from the README. The Library is empty (`$V library 00-empty` reports `work records: 0`).

- **Before.** Run `$V screenshot 00-before-add`. It shows `No Works`.
- **Add.** Tap `+`. On iPhone 17 it sits near (364, 84) pt, but read it off a fresh screenshot. Take screenshots until a row appears (1 to 3 s). The row reads `Sample Work` / `Pages: 1` / `Downloaded: 1`, `No Works` is gone, and the banner is still shown.
- **After.** Run `$V screenshot 01-after-add`.
- **Side effect.** Run `$V library 01-after-add`. It shows `work records: 1`, and the record has `"title":"Sample Work"`, `"kind":"comic"` and one chapter with one page whose `sourceEntry` is `p01-vertical-grid.png`. `files/pageImage/<id>.png` exists, and `outbox.json` lists the Work ID and that file.
- **Persist.** Run `$V relaunch`, then `$V screenshot 02-after-relaunch` and `$V library 02-after-relaunch`. You see the same single row and the same record ID.
- **Stable-handle check.** Run `$V ui-test testAddingASampleWorkListsItWithOnePage testTheOfflineBannerShowsWithoutBlockingAdding`. The summary reports 2 passed.

## Gotchas

- The row takes a second or two to appear on an Intel Mac. A screenshot right after the tap still shows `No Works`. Wait for the change before you call it failed.
- Every tap adds another Work with the same name. Count records in the dump, not names on screen.
- The `ui-test` methods use their own Libraries, so their Works never show in `Verify-<run>`.
