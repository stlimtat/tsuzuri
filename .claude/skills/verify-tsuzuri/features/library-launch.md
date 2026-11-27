# Library launch and status

Opening Tsuzuri shows the Library: the Works the user has imported or, with none, a "No Works" empty state. A footer names the build and commit. When iCloud cannot take changes, a yellow banner says so without blocking anything.

## Sub-features

- `launch-empty` shows the "No Works" empty state and no Work rows on a fresh Library.
- `launch-build-info` shows `Build <number> · <short commit>`, where the commit is the installed build's commit (or `dev` when none was stamped).
- `launch-offline` shows the banner "iCloud is unavailable…" and the line `iCloud: Offline`.

## How to get to it (user POV)

- Launch the app from the home screen.
- Bring it back to the foreground after leaving it (this triggers a sync request and a list refresh).

## Driving it with verify-tsuzuri

Preconditions:

- Baseline from the README. `$V launch` has just run.

- **Launch.** Run `$V launch`. It ends with `run=… udid=…` and saves `00-launched.png`.
- **Empty state.** Take a tool `screenshot`. The title reads `Library (Debug)`, the centre reads `No Works` / "Add a sample Work to try the Library.", and there is no row. `$V library 00-empty` reports `work records: 0`.
- **Build footer.** In the same screenshot, the footer reads `Build 1 · <first 7 characters of git rev-parse HEAD>`. `$V doctor` reports the same commit on its `build:` line.
- **Offline status.** The banner at the top reads "iCloud is unavailable. Your changes are kept on this device and sync when iCloud is back." and the footer reads `iCloud: Offline`.
- **Foreground.** Use the tool's `button` `HOME`, then `$V relaunch` (or tap the app icon). The Library reappears unchanged.
- **Stable-handle check.** Run `$V ui-test testEmptyLibraryShowsNoWorksAndTheBuildInfo testTheOfflineBannerShowsWithoutBlockingAdding`. The summary reports 2 passed.

## Gotchas

- `iCloud: Offline` is the only status this harness can produce. Do not claim `Synced` behavior from it.
- A locally built app shows the commit `$V build` stamped. A build made without `TSUZURI_COMMIT` (Xcode Run, `scripts/build-app.sh` alone) shows `dev`.
- The first launch on a fresh simulator can take minutes. If `launch` times out, `doctor` usually shows the app up.
