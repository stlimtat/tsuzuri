# R1 · App Shell

_App targets (iPhone, iPad, Mac) · Tier 3 · Depends on: all modules_

## Purpose
Navigation, screens that tie modules together, settings and platform polish.

## Screens
1. **Onboarding:** short intro; choose "I want to understand the story" (Story mode) or "I'm learning Japanese" (Learn mode) — sets defaults only; voice quality tip.
2. **Library** (from Library & Import).
3. **Work detail:** Chapters, Cast tab, Renders list.
4. **Panel editor:** Pages with Panel polygons; add, delete, reshape, split, merge, reorder; Page split and reorder; Chapter split and merge; Bubble editing and orientation override; Script editor (source text, translation, Speaker per Line); "check Panels" flags from Panel Detection; undo/redo everywhere.
5. **Player** (from Player).
6. **Render sheet** (selection, direction presets, note, consent) from Render Client.
7. **Settings:** mode (Story/Learn), voices, Read-aloud speed and pauses, delivery resolution, local Render storage budget and "Clear downloaded Renders", iCloud status, account (Sign in with Apple, sign out, **delete account**), subscription and credits (manage, restore), BYOK, video-partner consent, privacy policy, licences of third-party components.

## Platform requirements
- **iPhone:** compact layouts; Panel view first.
- **iPad:** split view (Library + content), Pencil for drawing Panels and Bubbles, drag and drop import, keyboard shortcuts.
- **Mac:** native SwiftUI macOS target; menus and keyboard shortcuts for all editor actions; multiple windows (one per Work).
- **Accessibility:** VoiceOver labels on all controls; Dynamic Type; sufficient contrast; Reduce Motion respected in Panel transitions.
- All strings localizable (English only at launch).
- Sign in with Apple appears **only** when the user first tries a paid feature.

## Acceptance tests
- UI tests for every screen on iPhone, iPad and Mac.
- Accessibility audit (Xcode Accessibility Inspector) with no critical issues.
- No glossary _Avoid_ terms in UI strings (automated string check).
- Account deletion reachable in ≤3 taps from Settings.
