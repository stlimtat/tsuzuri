# R1 · Render Client

_Package: `RenderClient` · Tier 1 · Depends on: Comic Structure, Persistence, Cast, Backend client_

## Purpose
Let a paying user request a Render of 1–10 consecutive Panels, track it as a background job, and store the result (ADR 0001).

## User flow
1. In the Player or Panel editor, the user selects a run of **1–10 consecutive Panels** in one Chapter and taps **Render**.
2. **First time only:** consent sheet: "The Panels you render, their dialogue and your Cast references are sent to our video partner to make the video. Nothing is kept after the video is made." Accept is stored per account; it can be withdrawn in Settings (which disables Renders).
3. **Gate:** Sign in with Apple if not signed in; then entitlement check (subscription allowance, credits, or BYOK with an active subscription). Out of allowance and credits → credit pack offer (Payments). Allowance amounts are **not shown** to the user.
4. **Direction:** presets — camera (static, slow push-in, pan, dynamic), intensity (calm, normal, dramatic), mood (neutral, comic, tense, sad, romantic) — plus an optional note **≤100 characters**.
5. **Preparation check on device:** Lines exist for all Bubbles in the selected Panels (vertical Bubbles may need cloud OCR first, which is offered); Speakers set or left for the backend to propose.
6. Submit → job appears as "Rendering…" on those Panels. The user keeps reading; Read-aloud performs those Panels in the meantime.
7. **Push notification** when ready or failed. The video downloads, is stored via Persistence (backed up to iCloud) and plays in the Player.
8. **Re-render** any time (paid again). Edits to the inputs mark a Render stale (Comic Structure).

## Job payload (to `POST /v1/renders`)
- Panel images: crops of the selected Panels only, at the provider's input size.
- Script for those Panels: Lines (source text, translation), Speakers.
- Cast references for Characters appearing as Speakers or tagged in those Panels (crops, names, voice descriptions).
- Story so far: the Chapter's `storySummary` (editable by the user; generated and updated by the backend).
- Direction: presets and note.
- Target delivery resolution (below), reading mode (Story/Learn decides the spoken language: target language in Story mode, source language in Learn mode).
- Optional BYOK: provider ID + key from the Keychain, sent per request only.

## Results
- Video file at the delivery resolution; updated story summary; proposed Speakers for Lines without a user-set Speaker; provider ID; consumption units used (stored for support, not shown).
- **Failures:** if the provider refused or failed and charged us, the attempt is charged to the user (ADR 0005); the UI says plainly why it failed (e.g. "the video partner declined this content") and that it used a Render.

## Delivery resolution
- Defaults: **iPhone on mobile data 240p**, **iPad 360p**; per-device-model defaults come from a backend-delivered config table (so they can change without an App Store update). **Mac default: 360p until the Lead sets it.**
- User can override in Settings (240p / 360p / 480p / 720p, provider-dependent). Changing resolution later requires a new Render.

## Limits
- 1–10 Panels per Render. **Clip length is capped by the selected provider's maximum per request**; the backend splits the clip time across Panels by dialogue length.

## Public interface (sketch)
```swift
public protocol RenderRequesting {
  func submit(_ request: RenderRequest) async throws -> Render            // status .queued
  func status(_ id: Render.ID) async throws -> Render
  var updates: AsyncStream<Render> { get }                                  // driven by push + polling fallback
  func cancel(_ id: Render.ID) async throws                                 // allowed while queued
}
```

## Acceptance tests
- Selection rules: 0 or 11 Panels, or non-consecutive Panels, cannot be submitted.
- Consent sheet appears once per account; withdrawal blocks submission.
- Unentitled user: no request leaves the device; correct sign-in / purchase prompt.
- Payload capture test: only selected Panel crops, their Lines, relevant Cast data and the summary are sent; never full Pages, never other Chapters.
- Push and polling both complete a job; app killed mid-job still receives the result on next launch.
- Ready Render plays in the Player and appears on a second device via iCloud.
- Note >100 characters rejected client-side and server-side.
