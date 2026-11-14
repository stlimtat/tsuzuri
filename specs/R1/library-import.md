# R1 · Library & Import

_Package: `LibraryImport` · Tier 3 · Depends on: Comic Structure, Persistence_

## Purpose
Bring the user's comics into the Library and let them browse it.

## Import
1. **Entry points:** document picker (Files), share sheet / "Open in", drag and drop (iPad, Mac), Photos picker.
2. **Formats (R1):** CBZ, ZIP, a folder of images, individual images (JPEG, PNG, HEIC, WebP), Photos selection. **CBR (RAR)** only if a permissively licensed decoder is approved by the Lead (e.g. libarchive, BSD); otherwise CBR shows "not supported yet".
3. **Page order:** natural sort of file names (`page2` before `page10`), ignoring hidden and non-image files (`__MACOSX`, `.DS_Store`, `Thumbs.db`).
4. **Chapter detection:** one Chapter per top-level folder inside the archive if folders exist; otherwise file-name patterns (`ch01`, `第1話`, `c001`); otherwise one Chapter. The user can split and merge afterwards (Comic Structure).
5. **Work creation:** `kind = .comic`; title from file or folder name; `readingDirection` defaults from the source language (Japanese → right-to-left); `sourceLanguage = ja`, `targetLanguage = en`.
6. **Large imports** run in the background with progress and cancel; the Work appears immediately and fills in.
7. **Safety:** archives are untrusted. Reject path traversal entries, cap total uncompressed size (default 4 GB) and entry count (5,000), and detect zip bombs (compression ratio limit). Images are decoded with system frameworks only.
8. After import, Panel Detection runs automatically per Page in the background (on device, free).

## Library UI
- One Library for all Works (comics now, books from R1.5), grid and list views, filter by kind, sort by title / recently opened / recently added, search by title.
- Work detail: Chapters with thumbnails, reading progress, Render count.
- Delete Work (confirmation; removes from all devices).

## Public interface (sketch)
```swift
public protocol Importer {
  func importItems(_ urls: [URL]) -> AsyncThrowingStream<ImportProgress, Error>
  func importPhotos(_ items: [PhotosPickerItem]) -> AsyncThrowingStream<ImportProgress, Error>
}
```

## Acceptance tests
- Golden archives import with correct Page order and Chapter split (fixtures: folders-per-chapter, flat with `ch` names, flat without names).
- Malicious fixtures (path traversal, zip bomb, 10,000 tiny entries, corrupt images) are rejected with a clear message and no crash.
- 300-Page CBZ imports on an iPhone 12-class device in under 30 s with memory under 300 MB.
- Import from Files, share sheet, drag and drop (iPad/Mac) and Photos all work on physical devices.
