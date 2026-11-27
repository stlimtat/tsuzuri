# Delete a Work

A user can delete a Work from its context menu or its swipe actions. A confirmation, `Delete “<name>”?`, warns that the Work goes from every device and iCloud. Cancel keeps it, and Delete removes the row, its record and its files and leaves a tombstone to sync.

## Sub-features

- `delete-confirm` asks `Delete “<name>”?` with the iCloud warning before anything is removed.
- `delete-cancel` keeps the Work when the user cancels or taps outside the popover.
- `delete-remove` removes the row (the empty state returns when it was the last one), the record and the Page file.
- `delete-tombstone` records the deletion for iCloud (`deletions.json` / outbox tombstone).

## How to get to it (user POV)

- Long-press a Work row and choose `Delete`.
- Swipe a Work row left and tap the red `Delete`.

## Driving it with verify-tsuzuri

Preconditions:

- Baseline from the README, plus one Work added through [Add a sample Work](./add-sample-work.md) (two if you want to prove both entry points).

- **Ask first.** Long-press the row and tap `Delete`. A dialog titled `Delete “Sample Work”?` appears with "This removes the Work and its files from this device, your other devices and iCloud." Run `$V screenshot 08-delete-confirm`.
- **Cancel.** On iOS 26 iPhone the dialog is a popover without a `Cancel` button. Tap well below it (about (200, 780) pt). The dialog closes and the row stays. `$V library 09-delete-cancelled` still reports `work records: 1`.
- **Delete.** Open the dialog again and tap its red `Delete`. The row goes, and `No Works` returns if it was the last Work. Run `$V screenshot 10-deleted` and `$V library 10-deleted`. The dump shows `work records: 0`, no `files/pageImage/<id>.png`, and the deleted Work ID in `deletions.json` or in the outbox `tombstones`.
- **Swipe entry.** Add another Work, swipe its row left and tap `Delete`. The same confirmation appears. Confirm it and check the same end state.
- **Stable-handle check.** Run `$V ui-test testDeletingAWorkAsksFirstAndCancelKeepsIt`. The summary reports 1 passed. This covers the context-menu entry only.

## Gotchas

- Where the popover shows a `Cancel` button (iPad, other iOS versions), use it. Tapping outside is only the iPhone iOS 26 path.
- The swipe action's `Delete` and the dialog's `Delete` share a label. After you swipe, wait for the dialog before tapping `Delete` again.
- A Work whose files were already uploaded could have them evicted rather than present. With iCloud unavailable here, the files are always local.
