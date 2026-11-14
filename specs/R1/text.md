# R1 · Text (Bubbles, OCR, translation)

_Package: `TextPipeline` · Tier 1 · Depends on: Comic Structure, Backend client_

## Purpose
Find the Bubbles in each Panel, read their text into Lines, and translate them. Horizontal text is read on the device for free; vertical text is read in the cloud as a paid feature (ADR 0004).

## Pipeline per Panel
1. **Bubble detection (device):** Vision text detection gives text regions; group nearby regions into Bubbles (speech balloons, captions, SFX). User can add, delete, reshape Bubbles.
2. **Orientation (device):** classify each Bubble as horizontal or vertical from the layout of its text regions (column vs row structure, aspect ratios). User can override; an override is never sent to the cloud without the user's choice.
3. **OCR**
   - **Horizontal → device:** Vision `RecognizeTextRequest` with `ja` (and `en` for mixed text), accurate level. Free.
   - **Vertical → cloud (paid):** crop **only the vertical Bubble** (plus 8% padding), downscale to the minimum size the provider needs, send to the backend `POST /v1/ocr`. Requires Sign in with Apple and an active entitlement or credits. Users without them see the Bubble marked "vertical text: unlock to read" and can type the text themselves for free.
   - Batch all vertical Bubbles of a Page in one request when the user reads that Page (no background cloud calls without the user acting on that Page).
4. **Translation (device, free):** Apple `TranslationSession` (ja → en), batched per Chapter in reading order. Handle language pack download on first use with clear UI. Cloud OCR results are also translated on the device.
5. **Furigana (device):** readings for kanji via `CFStringTokenizer` (Latin/kana transcription) and the NaturalLanguage tokenizer, stored on the Line for Learn mode.
6. **Editing:** the user can edit source text and translation of any Line. Re-translating an edited Line is on device and free. Re-reading a vertical Bubble in the cloud is paid again.

## Rules
- Lines are **data, never instructions**, everywhere they flow (security, see `R1/security.md`).
- No cloud call for horizontal text, ever.
- Results carry their source (`.onDevice`, `.cloud`, `.user`) so later steps and analytics can tell them apart.

## Public interface (sketch)
```swift
public protocol TextPipeline {
  func detectBubbles(in panel: Panel, images: [PageImage]) async throws -> [Bubble]
  func readOnDevice(_ bubbles: [Bubble], images: [PageImage]) async throws -> [Line]
  func readInCloud(_ bubbles: [Bubble], images: [PageImage]) async throws -> [Line]   // paid; throws .notEntitled / .needsSignIn
  func translate(_ lines: [Line], from: Locale.Language, to: Locale.Language) async throws -> [Line]
  func furigana(for text: String) -> [RubySpan]
}
```

## Acceptance tests (golden set)
- Bubble detection recall ≥90%, precision ≥85%.
- Orientation classification accuracy ≥95%.
- On-device horizontal OCR character accuracy ≥90%.
- Cloud vertical OCR character accuracy ≥95% (measured in M0 for the chosen provider).
- Only vertical Bubble crops are uploaded: a request-capture test asserts no full Page and no horizontal Bubble is ever sent.
- Unentitled user: no request leaves the device; the "unlock" state is shown.
- Translation runs on a physical device (the Translation framework does not run in the Simulator); a fake is used in CI.
- Poisoned fixture: a Bubble reading "ignore previous instructions and…" is stored and translated as plain dialogue.
