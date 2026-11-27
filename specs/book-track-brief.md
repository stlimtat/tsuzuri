# M2–M4 book track: grilling outcome (2026-11-25)

**Order change:** the EPUB work comes before comics.
- The comic import and Panel editor (the old M2) move to M5 or later.
- Text, Player and Renders shift after them.
- This needs an ADR and an update to `specs/00-overview.md` §9.

## Cross-cutting
- **Platforms:** iPhone and iPad. No Mac target and no Pencil yet.
  - Code editing is iPad only (as R5 says).
  - iPhone gets metadata editing, the reader and Read-aloud.
- **Undo:** per open Work, in memory. It's cleared on close or relaunch, and when a sync replaces the Work.
- **Sync:** reuse the M1 sync. The Work record goes through CloudKit and the EPUB through the iCloud Drive file container, with whole-Work last-writer-wins.
- **libarchive (approved):** vendor a pinned release of the BSD source as a C target.
  - Keep only the ZIP read/write parts, plus RAR read for later CBR.
  - Record its licence in LICENSES and add it to the allowlist.
  - The iOS SDK ships no libarchive headers, so we can't link the system copy.
- **XML:** the system libxml2, which has public headers. No new dependency.

## M2: EPUB core, Library, metadata, lookup
1. **`EPUBCore`:** open and save EPUB 2/3.
   - On save, `mimetype` is the first entry, stored uncompressed.
   - Untouched OPF stays byte-for-byte.
   - Round-trip fixtures (R1.5).
2. **Import:** an EPUB becomes a Work with `kind = .book`. Entry points follow `library-import.md`.
3. **DRM:** detect `META-INF/encryption.xml` / `rights.xml` and refuse the import with an explanation.
4. **The real Library screen (#30),** books first, with covers from metadata.
5. **Metadata editor:**
   - title and sort title
   - authors with file-as
   - series and number, written as EPUB 3 collection + calibre meta
   - cover, set in both EPUB 3 and EPUB 2
   - ISBN identifier, publisher, date and language
   - description and subjects
   - contributors with roles
6. **Metadata lookup:**
   - **Path:** straight from the device to free keyless catalogs.
     - Open Library for general titles; openBD for Japanese ISBNs.
     - Only the ISBN, title or author leave the device.
   - **New ADR:** amends ADR 0004 to allow free keyless public lookups.
   - **Terms:** the Lead confirms both catalogs' terms allow use from a paid app before release.
   - **User-Agent:** `Tsuzuri/<version>` plus a support email from a build setting, filled in before the release that ships lookups.
   - **Query input:**
     - an ISBN already in the EPUB
     - a typed ISBN-10/13, checksum-validated
     - a camera barcode scan (VisionKit; needs camera permission text)
     - title + author search, which returns several candidates
   - **Applying results:** the user picks a match, then reviews current vs found per field with checkboxes, then applies it as one undoable edit.
7. **Share:** a share sheet to any EPUB app, with the Apple Books guide (Books adds a new copy, so delete the old one).

## M3: content editor (R5 items 1–3)
- **File browser:** add, rename, delete and reorder spine items.
- **Code editor:** Runestone (MIT, Tree-sitter grammars) for XHTML/CSS/OPF/NCX. Needs an allowlist entry.
- **Live preview:** WKWebView beside the editor, synced to the cursor.
- **Save check:** libxml2 well-formedness on edited XHTML/OPF/NCX, plus a check that manifest files exist. A failure blocks the save and shows the error line.
- **Deferred:** the book checker, TOC editor, find/replace and tools.

## M4: reader + Read-aloud (R2 subset)
- **Spike first:** Readium Swift Toolkit (BSD-3) vs our own WKWebView, run on the fixtures (reflowable, fixed layout, vertical Japanese RTL). Default: Readium, after allowlist review of it and its dependencies.
- **Reading settings:** fonts, size, margins, spacing, themes, paged or scrolling.
- **Read-aloud:**
  - `AVSpeechSynthesizer` with sentence highlighting (<150 ms drift)
  - speed control and auto page turn
  - background audio with lock-screen controls
  - a `ReadAloud` package that comics reuse later
- **Navigation and sync:** TOC navigation, and reading position synced through iCloud.
- **Deferred:** bookmarks/highlights/notes, search, Learn mode, sleep timer, voice choice.

## Still open (belongs to the comic spec later)
- Panel Detection in the comic milestone (Q1).
