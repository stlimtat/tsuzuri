# Rename a Work

A user can rename a Work from its context menu or its swipe actions. The `Rename Work` alert refuses a blank name, trims surrounding spaces, and the new name survives a relaunch.

## Sub-features

- `rename-blank` keeps `Save` disabled while the name is empty or only spaces.
- `rename-trim` saves `  Night Market  ` as `Night Market`.
- `rename-cancel` leaves the name unchanged.
- `rename-persist` keeps the new name after a relaunch.

## How to get to it (user POV)

- Long-press a Work row and choose `Rename` from the context menu.
- Swipe a Work row left and tap `Rename`.

## Driving it with verify-tsuzuri

Preconditions:

- Baseline from the README, plus one Work added through [Add a sample Work](./add-sample-work.md).

- **Context menu entry.** Long-press the row (`tap` with `duration: 1.2`). A menu shows `Rename` and `Delete`. Tap `Rename`. The alert `Rename Work` appears with the field prefilled `Sample Work`, plus `Cancel` and `Save`.
- **Blank refused.** Clear the field (`press_key` `select_all`, then `delete`) and type three spaces with `text`. `Save` is greyed out. Run `$V screenshot 05-rename-blank`.
- **Trimmed save.** Clear again, type `  Night Market  ` and tap `Save`. The row reads `Night Market`, with no leading spaces. Run `$V screenshot 06-renamed` and `$V library 06-renamed`. The record's `"title"` is `"Night Market"` and the record ID is unchanged.
- **Cancel.** Reopen the alert, type `Discard me` and tap `Cancel`. The row still reads `Night Market`.
- **Swipe entry.** Swipe the row left (from x≈350 to x≈80 at the row's y). `Rename` and `Delete` buttons appear. Tap `Rename` and save `Swiped Name`. The row and the record both read `Swiped Name`.
- **Persist.** Run `$V relaunch`, then `$V screenshot 07-rename-relaunch`. The row reads `Swiped Name`.
- **Stable-handle check.** Run `$V ui-test testRenamingAWorkRefusesABlankNameAndSavesTheTrimmedOne testARenamedWorkSurvivesARelaunch`. The summary reports 2 passed. This covers the context-menu entry only.

## Gotchas

- The XCUITest flow covers only the context menu. The swipe entry is proven only by driving it with the tool.
- The rename is checked on the row's rendered name and the record's title, not on the text typed into the field.
- Typing into the alert needs the simulator's software or hardware keyboard to take focus. If the `text` action types nothing, tap the field first.
