# R1 · Read-aloud

_Package: `ReadAloud` · Tier 2 · Depends on: Comic Structure_

## Purpose
Speak a Panel's Lines live on the device, free. It is how every Panel without a Render is "performed", and it keeps the Player going while a Render is being made.

## Requirements
1. `AVSpeechSynthesizer` with system voices. Prefer installed **Premium**, then **Enhanced**, then default voices; offer a guide to download better voices (Settings → Accessibility → Spoken Content → Voices).
2. **Story mode:** speaks the translations in the target language (English voice).
3. **Learn mode:** speaks the source text (Japanese voice); optional second pass speaking the translation; speed 0.5×–1.5×; optional pause after each Line (0–5 s, or "wait for tap") for shadowing.
4. Lines are spoken in reading order. Lines with a Speaker can use a per-Character system voice chosen by the user (optional mapping stored on the Character).
5. Emits progress events (current Line, word range) so the Player can highlight subtitles.
6. Respects silent mode and audio session interruptions; continues in the background only while the Player is active.
7. No network use.

## Public interface (sketch)
```swift
public protocol ReadingAloud {
  func speak(_ lines: [Line], mode: ReadingMode, settings: ReadAloudSettings) -> AsyncStream<ReadAloudEvent>
  func stop()
  func availableVoices(for language: Locale.Language) -> [VoiceInfo]   // with quality tier
}
```

## Acceptance tests
- Story and Learn modes speak the right language and order (unit tests with a fake synthesizer).
- Word-range events drive highlighting within 100 ms (device test).
- Pause-after-Line and wait-for-tap behave as configured.
- Works with no network.
