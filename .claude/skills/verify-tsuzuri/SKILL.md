---
name: verify-tsuzuri
description: Build, launch and drive the Tsuzuri iOS app in its own throwaway iOS Simulator, the way a user does, and capture proof (screenshots, the on-disk Library, XCUITest results) that a change works. Use before calling any app-facing change done, when asked to verify, QA, smoke-test or "prove it works" in Tsuzuri, or when a pstack playbook asks for verification on the real surface.
---

# Verify Tsuzuri

Tsuzuri's user surface is an iPhone app (`Apps/iOS`, scheme `Tsuzuri`, bundle `net.stlim.tsuzuri`). Today the app is one screen, the debug **Library** (`Apps/iOS/Tsuzuri/DebugLibraryView.swift`): a list of Works with add, view page, rename, delete and an iCloud status. iPad and macOS targets and the EPUB/book track (milestones M2 to M4) are not in the app yet. Add their features to [`features/`](features/README.md) when they land.

Everything goes through one helper. Run it from anywhere in the checkout:

```bash
V=.claude/skills/verify-tsuzuri/scripts/verify-tsuzuri
$V            # prints the command list
```

Run state and evidence live in `<repo>/.verify/<run>/` (gitignored). `.verify/latest` points at the newest run. Set `VERIFY_RUN=<run>` to address an older one.

## Launch

1. `$V build` builds `Tsuzuri.app` (Debug, iOS Simulator, unsigned) through `scripts/build-app.sh`, stamped with `git rev-parse HEAD` (with `-dirty` when tracked files have changes). A warm build takes about 30 s. A cold one on this Intel Mac takes several minutes, so run it in the background.
2. `$V launch` creates a **new simulator named `tsuzuri-verify-<run>`** (an iPhone 17 on the newest installed iOS runtime), boots it, installs the build and launches it with `-TsuzuriUITesting` and `TSUZURI_UI_TEST_LIBRARY=Verify-<run>`. That debug-only switch (`Apps/iOS/LibraryDebug/LibraryLaunch.swift`) opens an **empty Library in the app's tmp directory with iCloud unavailable**, so the run never touches a real Library or iCloud account. On first boot it takes 1 to 5 minutes.
3. Ready means the app process is running and has created `works/` in its Library. `launch` waits up to 120 s for that, then prints `run=… udid=… library=… artifacts=…` and saves `00-launched.png`. If it times out, run `$V doctor`. The app is often up and only slow.

There is no seed data. Every journey starts from an empty Library and makes its own Works with **Add Sample Work** (one Page, `p01-vertical-grid.png` from the golden set).

## Doctor

`$V doctor` is read-only. It checks four things: this run's simulator exists, carries this run's name and is booted; the installed app's `TsuzuriCommit` matches the checkout's HEAD; the app process is running; and the run's Library exists on disk. It exits non-zero and names the failing line when the instance is not worth driving. Run it first, and again whenever anything looks off.

- `build: STALE`: you changed code, or `ui-test` reinstalled its own build. Run `$V build` (if you changed code), then `$V reinstall`. The reinstall keeps the app's data, so the run's Library and its Works survive.
- `app: NOT RUNNING`: run `$V relaunch`. It reopens the same Library.

## Drive

There are two harnesses. Use both for a proof: the tool for the path a user takes, XCUITest for stable-handle assertions.

**1. The Claude Code iOS Simulator tool (`mcp__Claude_Code_iOS_Simulator__control`) is the user's path.** Get the UDID from `$V env`, then pass `device: <UDID>` on every call so you never drive another simulator. Call `attach` once to open the live panel. Then loop: `screenshot`, tap, `screenshot`. Coordinates are in device points (402×874 on iPhone 17). Read them off a fresh screenshot: the image is scaled, so multiply image pixels by 402 / image width. Long-press is `tap` with `duration: 1.2`. Type with `text`. Swipe a row left with `swipe` from x≈350 to x≈80 at the row's y.

**2. XCUITest (`$V ui-test [testMethod...]`) uses stable handles.** It runs `Apps/iOS/TsuzuriUITests/LibraryFlowTests.swift` on this run's simulator, either all of it or only the named methods. The result bundle and a JSON summary go in the artifacts folder. Each test launches its own empty Library, so these tests do not see Works you added by hand. The run reinstalls the app from the test build, so `doctor` reports `STALE` afterward. To check new behavior, add a test method there and run it by name.

Stable handles (accessibility identifiers and labels in `DebugLibraryView.swift`):

| Handle | What it is |
| --- | --- |
| `addSampleWork` | The toolbar `+` button (top right), "Add Sample Work" |
| `workRow` | One Work row. Its label combines name, `Pages: N` and `Downloaded: N` |
| `emptyLibrary` | The "No Works" empty state |
| `pageImage` | The Page image in the sheet that opens when you tap a row. Close it with the `Done` button |
| `Rename Work` alert, `renameField`, `Save`, `Cancel` | The rename flow, opened from the context menu or the swipe action |
| `Delete “<name>”?` dialog, `Delete`, `Cancel` | The delete confirmation |
| `syncBanner`, `syncStatus` | The yellow iCloud banner (top) and the `iCloud: <status>` line (bottom) |
| `buildInfo` | `Build <number> · <short commit>` (bottom) |

**Read the side effect.** `$V library <name>` dumps the run's Library to `<artifacts>/<name>.txt`: each Work's JSON record in `works/`, the Page files in `files/`, and `outbox.json` / `deletions.json`, which are what would sync to iCloud. Every mutation journey checks this dump, not only the screen.

**Check persistence.** `$V relaunch` terminates the app and relaunches it on the same Library.

## Evidence

Evidence goes to `.verify/<run>/artifacts/`. Name files `NN-<step>.png` / `.txt` in journey order.

- `$V screenshot <name>` saves a full-resolution PNG from `simctl`. Take one before and one after every action that you claim works. The tool's own screenshots are for steering and are not saved to the artifacts folder.
- `$V library <name>` saves the on-disk state that proves the mutation (record written, renamed or removed, file present, outbox entry, tombstone).
- `$V ui-test` saves `ui-test-<time>.xcresult` with `-summary.json` / `-tests.json`. Open the bundle with `open <path>` to see failure screenshots.

Proof standards:

- Drive the real user path: taps, menus and alerts. `-TsuzuriUITesting` is allowed because it only swaps the iCloud backends for an unavailable one. That is a production boundary: the same code path runs when a user is signed out of iCloud.
- Capture the action and the resulting state, and show the Library dump alongside the screen.
- `iCloud: Offline` and the banner are expected in every run. An unsigned simulator build cannot reach iCloud. Never report sync as verified from this skill.
- Report each journey as **verified**, **failed** (with the step and what you observed) or **not driven** (with why). Do not report a journey as verified through a different entry point than the one named.

## Cleanup

`$V cleanup` terminates the app, shuts down and deletes **only this run's simulator** (by UDID, and only if it still carries the `tsuzuri-verify-<run>` name), then lists the kept evidence. It never touches other simulators, never kills processes by name and never deletes `.verify/`. Run it after every run, failed ones too. Remove old evidence yourself with `rm -rf .verify/<run>` when you no longer need it.

## Isolation and limits

- Each run owns its simulator, so two runs can exist side by side. Do not run two `ui-test`s at once: they share the derived data at `$TMPDIR/tsuzuri-ui-test/derived`. Never point the helper or the tool at the user's own simulators (`iPhone 17` etc.). `scripts/ui-test.sh` uses those, and the helper does not.
- These cannot be driven here: live iCloud sync between devices, the `iCloud full` banner, `Synced` / `Syncing` status and pull-to-refresh bringing in remote Works. They need a signed build and an iCloud account (`docs/release/testflight-checklist.md`). The logic for them is covered by `scripts/test.sh Persistence` and `scripts/test.sh App`, which are tests, not verification.
- The build is x86_64 on this Mac (`uname -m`). `ui-test` builds for the host architecture only.

## Feature map

[`features/README.md`](features/README.md) is the maintained list of user-facing journeys and how to prove each one. A proof of a change covers every entry point the map lists for the features the change touches. Keep the map current with `/pstack:maintain-verification-skill`.
