# Tsuzuri verification map

This directory is the maintained source for verifying Tsuzuri's user-facing behavior. Read this index before driving the app, then use the matching feature file as the recipe. The app today is the debug Library screen. The App Shell, the Player and the EPUB reader (M2 to M4) replace or join it later. Add a file here for each one as it ships.

## Baseline preconditions

- `V=.claude/skills/verify-tsuzuri/scripts/verify-tsuzuri`
- `$V build` then `$V launch`. You get this run's own simulator `tsuzuri-verify-<run>` with the app open on an empty Library `Verify-<run>` and iCloud unavailable.
- `$V doctor` prints `doctor: healthy`.
- `$V env` gives the `UDID` to pass as `device` on every iOS Simulator tool call.
- Never drive a simulator that this run did not create.

## Driving conventions

- Start every recipe from the baseline. The Library starts empty, and there is no seed data.
- User path: the iOS Simulator tool (`screenshot`, `tap`, `text`, `swipe`), with coordinates read off a fresh screenshot. Do not reuse coordinates across layouts.
- Stable-handle path: `$V ui-test <method>` runs the matching `LibraryFlowTests` method. Afterward `doctor` reports `STALE`: run `$V reinstall` before driving by hand again.
- Mutations take a second or two to show on this Intel Mac. Take the after screenshot only once the screen has changed. The tool's tap result says whether it did.
- The UI uses the domain words from `CONTEXT.md`: Library, Work, Page.

## Proof and skip reporting

- UI proof is a before and an after screenshot (`$V screenshot NN-step`), with the `Build <n> · <commit>` footer visible.
- Mutation proof adds `$V library NN-step`: the Work record in `works/`, the Page file in `files/`, and the `outbox.json` / `deletions.json` entry.
- Persistence proof is `$V relaunch`, then a screenshot and a Library dump.
- Record the feature ID and the entry point with every artifact.
- Report an entry point you could not reach with the attempted step and the unmet precondition. Never report it as verified through a different entry point.

## Feature entry contract

Each feature file starts with an H1 and one paragraph on the user-visible behavior, then exactly four H2s in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with verify-tsuzuri`, `Gotchas`. Keep implementation details out. Name only user paths, stable handles, required state, commands and observable proof.

## Features

- [Library launch and status](./library-launch.md) covers the empty state, the build footer and the offline iCloud banner and status.
- [Add a sample Work](./add-sample-work.md) covers the toolbar add, the new row, the record on disk and persistence across relaunch.
- [View a Work's Page](./view-page.md) covers tapping a row, the Page sheet and closing it with Done.
- [Rename a Work](./rename-work.md) covers the context menu and swipe entry points, blank-name refusal, trimming, cancel and persistence.
- [Delete a Work](./delete-work.md) covers the context menu and swipe entry points, the confirmation, cancel and the tombstone.

## Not drivable here

- Live iCloud sync (`Synced`, `Syncing`, `iCloud full`, remote Works arriving on pull to refresh) needs a signed build with an iCloud account. See `docs/release/testflight-checklist.md`.
- The "Something went wrong" alert has no user path that reliably triggers it.
