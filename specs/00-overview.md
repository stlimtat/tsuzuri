# Tsuzuri: Specification Overview

_Status: accepted · Last updated: 27 Nov 2026 · Owner: Lead_

Read this first. It applies to every module and phase. The domain language is defined in `CONTEXT.md`; use those terms exactly in code, UI copy and specs. Decisions with lasting consequences are recorded as ADRs in `docs/adr/`.

## 1. Product

An app for iPhone, iPad and Mac for reading, understanding and editing the comics and books a user owns.

- **Launch focus (R1 Panel Reader):** read raw Japanese manga Panel by Panel. On-device OCR and translation for horizontal text, paid cloud OCR for vertical text, on-device Read-aloud, and paid AI-acted **Renders** that show how a run of Panels would look acted on screen.
- **Later:** a Calibre-style EPUB toolkit (metadata editing, reader with Read-aloud, conversion, content editing). No Calibre code is used (ADR-equivalent rule in §4).
- **Audiences:** fans who want to understand the story (**Story mode**) and language learners (**Learn mode**). One pipeline serves both; the mode only changes defaults (narration and subtitle language, furigana, speed, pauses).

## 2. Phases

| Phase | Name | Summary | Spec |
|---|---|---|---|
| **R1** | Panel Reader | Book track first (M2–M4: EPUB import, metadata editor and lookup, content editor, reader with Read-aloud; ADR 0008), then comic import, Library, Comic structure editing, Panel detection, OCR (horizontal on device, vertical in cloud), on-device translation, Read-aloud, Player, Cast, Renders, payments, iCloud sync | `specs/R1/*` |
| R1.1 | Learner Tools | Tap-to-lookup dictionary, saved words, Anki export | `specs/R1.1.md` |
| R1.5 | Metadata Editor Lite | Open an EPUB, edit title/author/series/cover, save, send to Apple Books | `specs/R1.5.md` |
| R2 | EPUB Reader + Read-aloud | Reflowable EPUB reading with Read-aloud and highlighting | `specs/R2.md` |
| R3 | Full Metadata Editor | All OPF metadata, web metadata lookup, bulk edit | `specs/R3.md` |
| R4 | Conversion | CBZ/CBR, DOCX, TXT/HTML/Markdown, text PDF, FB2, DRM-free MOBI/AZW3 → EPUB | `specs/R4.md` |
| R5 | Content Editor | HTML/CSS and table of contents editing, regex find/replace, book checker (iPad and Mac only) | `specs/R5.md` |

R1 is specified per module. Later phases are specified at phase level and are broken into module specs just before each phase starts.

## 3. Platforms and languages

- Native SwiftUI targets for **iPhone, iPad and Mac** from one codebase. **Minimum OS: iOS/iPadOS 18, macOS 15** (needed for `TranslationSession`).
- **Source language** Japanese at launch; Korean and Chinese later. **Target language** and UI language English at launch; others later. All UI strings are localizable from day one.

## 4. Non-negotiable principles

1. **No Calibre code or GPL code.** Calibre's features are reimplemented from scratch. Every dependency must be MIT, BSD, Apache-2.0 or similarly permissive, and is approved by the Lead before it is added.
2. **Users bring their own content.** No built-in content sources, catalogues, links or search for manga sites.
3. **On-device first; cloud only where the device can't do the job, and every cloud use is paid** (ADR 0004). Free: import, Library, editing, horizontal OCR, Apple Translation, Read-aloud. Paid: vertical OCR and Renders.
4. **We never subsidise AI use.** The user pays for every downstream AI call, including failed or blocked attempts that the provider charges for, through their allowance, credits or their own key (ADR 0005).
5. **Privacy:** page content lives only on the user's devices and in their iCloud. The backend stores the Apple account ID, entitlement and usage only; job inputs and outputs are deleted as soon as the job is done or delivered (ADR 0003).
6. **Renders are watched only inside the app.** No export or share (ADR 0001).
7. **Security by design** against the OWASP Top 10 for LLM Applications (2026), OWASP MASVS and the OWASP API Security Top 10, with a penetration test gate in every build cycle (ADR 0006).

## 5. Architecture

```
┌──────────────────────── App (SwiftUI, iPhone/iPad/Mac) ────────────────────────┐
│ App Shell ── Library & Import ── Player ── Payments                             │
│      │              │              │                                            │
│ Comic Structure (shared model, Lead-owned) ── Persistence & Sync (iCloud)        │
│      │              │              │              │                             │
│ Panel Detection   Text (OCR, translation)   Read-aloud   Cast   Render Client   │
└──────────────────────────────┬──────────────────────────────────────────────────┘
                               │ HTTPS (Sign in with Apple token, entitlement)
┌──────────────────────────────▼──────────────────────────────────────────────────┐
│ Backend: auth · entitlement · metering · OCR proxy · Render pipeline · providers │
└─────────────────────────────────────────────────────────────────────────────────┘
```

- **Monorepo** on GitHub; one Swift package per module; a thin app target per platform (ADR 0002).
- Modules depend only on the published protocols of other modules and on the shared model in `ComicStructure`. No module imports another module's internals.
- The app never talks to an AI vendor directly; only to our backend (ADR 0003).

## 6. Module map and ownership

| # | Module | Package | Tier | Depends on | Spec |
|---|---|---|---|---|---|
| 1 | Comic Structure (shared model) | `ComicStructure` | 1 (Lead) | none | `R1/comic-structure.md` |
| 2 | Persistence & Sync | `Persistence` | 1 | 1 | `R1/persistence-sync.md` |
| 3 | Library & Import | `LibraryImport` | 3 | 1, 2 | `R1/library-import.md` |
| 4 | Panel Detection | `PanelDetection` | 2 | 1 | `R1/panel-detection.md` |
| 5 | Text (Bubbles, OCR, translation) | `TextPipeline` | 1 | 1, 9 | `R1/text.md` |
| 6 | Read-aloud | `ReadAloud` | 2 | 1 | `R1/read-aloud.md` |
| 7 | Cast | `Cast` | 2 | 1, 2 | `R1/cast.md` |
| 8 | Render Client | `RenderClient` | 1 | 1, 2, 7, 9 | `R1/render-client.md` |
| 9 | Backend + API client | `/backend`, `BackendClient` | 1 | none | `R1/backend.md` |
| 10 | Player | `Player` | 2 | 1, 5, 6, 8 | `R1/player.md` |
| 11 | Payments | `Payments` | 2 | 9 | `R1/payments.md` |
| 12 | App Shell | app targets | 3 | all | `R1/app-shell.md` |
| 13 | Security | cross-cutting | 1 (Lead) | all | `R1/security.md` |

**Tiers** (ADR 0002): Tier 1 = most capable, most expensive agents; Tier 2 = mid-range; Tier 3 = cheapest. Any Tier 2–3 pull request needs Lead review. Only the Lead changes `ComicStructure`, `BackendClient` protocols or anything in `CONTEXT.md`.

## 7. Way of working for agents

1. Read `CONTEXT.md`, this overview, the relevant ADRs and your module spec before writing code.
2. Work in vertical slices. Each pull request is small, has tests, and passes CI.
3. **Spec → failing tests → implementation.** Acceptance tests in each spec are the definition of done.
4. Never change another module's public interface. Request the change from the Lead with a short proposal.
5. Use glossary terms in type names (`Panel`, not `Frame`). Terms listed under _Avoid_ must not appear in code or UI.
6. Code that only works on a device (Translation, speech voices, StoreKit, push) must have a protocol so it can be faked in tests, and must be verified on a physical device before merge.
7. Agents from different vendors cross-test each other's modules (see `R1/security.md`).

## 8. Golden test set

A shared fixture set in `/Fixtures/golden`, owned by the Lead, used by every module:

- 30+ Pages of openly licensed or self-drawn comics: vertical and horizontal text, borderless and slanted Panels, a two-Page Panel, a two-pages-in-one scan, SFX, small furigana, dense dialogue.
- Ground truth JSON for Panels (polygons and reading order), Bubbles, text orientation and Line text.
- "Poisoned" Pages and notes for security tests (text in Panels such as "ignore previous instructions").
- No commercial manga in the repository, screenshots or marketing.

## 9. R1 milestones

**R1 goal:** a reader installs Tsuzuri from the App Store on iPhone and iPad, and uses it to fix, edit and read the EPUBs they own, and then to read raw Japanese manga Panel by Panel with translation, Read-aloud and paid Renders. Everything free runs on the device, and the Library syncs through their own iCloud.

The book track (M2–M4) comes before the comic track (M5+) (ADR 0008). M0 Trials can run any time before M6.

| # | Milestone | Exit criteria |
|---|---|---|
| M0 | **Trials** (2–3 weeks, before M6) | Vertical OCR: compare 2+ cloud options on the golden set (accuracy, cost per Bubble). Video: compare 3+ providers on acting quality, Character consistency, voice consistency across 3 Renders of one Character, refusal rate on manga-style Panels, cost per second, retention policy. Pick 2 video providers and 1 OCR provider. Decide the voice approach (ADR 0001 open point). |
| M1 | Foundations | Monorepo, CI, `ComicStructure` v1, Persistence, golden set, security pipeline skeleton; an internal TestFlight build installed on the Lead's devices, with iCloud sync of Work records and files between them |
| M2 | EPUB core + Library + metadata | EPUB import (Files, Open in, share sheet, iPad drag and drop) with DRM refusal; the real Library screen for books and comics; metadata editor with undo and a byte-preserving save; free lookup through Open Library and openBD by ISBN, barcode or title/author with per-field review; share sheet with the Apple Books guide; books sync between devices (issue #37) |
| M3 | Content editor (iPad) | Spine file browser (add, rename, delete, reorder); Runestone code editor for XHTML/CSS/OPF/NCX; live WKWebView preview; save blocked on malformed XML or missing manifest files |
| M4 | EPUB reader + Read-aloud | Readium spike decided; reflowable, fixed-layout and vertical Japanese books readable with reading settings; Read-aloud with sentence highlighting (<150 ms drift), speed, auto page turn, background audio and lock-screen controls in a reusable `ReadAloud` package; TOC navigation; reading position synced through iCloud |
| M5 | Comic import + editing | CBZ/ZIP/images import, Chapter/Page/Panel editing with undo; per-entity merge (ADR 0007) before multi-device comic editing |
| M6 | Text | Bubbles, orientation, on-device OCR + translation; cloud vertical OCR behind sign-in and entitlement |
| M7 | Player + comic Read-aloud | Panel-by-Panel reading in Story and Learn modes |
| M8 | Cast + Renders | Cast tagging, Render jobs end to end with 2 providers, push notification, iCloud backup |
| M9 | Payments + hardening | Subscription, credit packs, BYOK, consumption limits; external pen test passed |
| M10 | Beta → App Store | External TestFlight with learners and fans; App Store review |

## 10. Pricing and unit economics

- **Free:** everything on the device.
- **Subscription:** one subscription with two internal allowances, vertical OCR and Renders, metered in downstream consumption units (tokens, video seconds). **Users are not shown their allowance.** When it runs out, the next paid action offers credit packs.
- **Credit packs:** consumable in-app purchases for use beyond the allowance.
- **BYOK:** paying subscribers can add their own key for a supported video provider; their key pays for video generation, the subscription pays for everything else.
- **Price formula** for every product: price ≥ (expected downstream AI cost at full use + per-user share of hosting, maintenance and pen testing) ÷ (1 − Apple's commission, 15% under the Small Business Program) × target margin. Prices are set after M0 using measured costs.

## 11. Legal and App Store

- Renders are personal viewing inside the app; no export or share.
- In-app account deletion (Sign in with Apple).
- Privacy label covers: Apple account ID, purchase history, usage data; cropped Bubble images and Panel images sent to processors for paid features only, with consent.
- Content policy: sexual content involving minors is blocked everywhere, by our moderation and by providers. Repeated abuse leads to account suspension.
- Marketing and screenshots use only our own or licensed art.

## 12. ADR index

| ADR | Decision |
|---|---|
| 0001 | Renders are AI-acted videos of 1–10 consecutive Panels, made in the cloud on request, watched only in the app |
| 0002 | Monorepo, one Swift package per module, Lead-owned shared model, agents by cost tier |
| 0003 | The app talks only to our backend, which hides the AI provider; no stored page content |
| 0004 | On-device first; cloud only where the device can't do the job, and always paid |
| 0005 | BYOK is for paying subscribers only and goes through our backend |
| 0006 | Security baseline (OWASP LLM Top 10 2026, MASVS, API Top 10) and a pen test gate |
| 0007 | The Library is one versioned JSON record per Work synced through CloudKit, not SwiftData; whole-Work last-writer-wins and tombstones in M1, per-entity merge before multi-device editing |
| 0008 | The book track (EPUB core, metadata, content editor, reader) comes before comics in R1; M0 gates M6; per-entity merge moves to before M5 |
| 0009 | Free keyless public catalog lookups (Open Library, openBD) go straight from the device, amending 0004 |
