# R1 · Cast

_Package: `Cast` · Tier 2 · Depends on: Comic Structure, Persistence_

## Purpose
Let the user define each Work's Characters once, so Renders keep Characters looking and sounding consistent and dialogue is voiced by the right Speaker.

## Requirements
1. **Tag a Character:** in the Panel editor, draw a box around a Character, enter a name and a short voice description (e.g. "young man, calm, low voice"). The crop becomes a reference image.
2. **More references:** add further crops of the same Character from other Panels (different angles help consistency). Up to 6 references per Character.
3. **Edit and delete** Characters; deleting clears them as Speaker (Comic Structure invariant 6).
4. **Speaker assignment:** Speakers are proposed by the backend during Render preparation (`R1/render-client.md`) and shown on each Line as "proposed"; the user can confirm or change them. The user can also set Speakers by hand at any time.
5. **Input limits (security):** name ≤40 characters, voice description ≤120 characters; both are passed to the backend as untrusted data and moderated there.
6. The Cast is stored per Work in the model and synced via iCloud. Reference crops are sent to the backend only as part of a Render the user requested.
7. Matching Characters inside a Render is done by the backend; the app does no face recognition.

## Public interface (sketch)
```swift
public protocol CastManaging {
  func addCharacter(name: String, voice: String, reference: ImageCrop, to work: Work.ID) async throws -> Character
  func addReference(_ crop: ImageCrop, to character: Character.ID) async throws
  func setSpeaker(_ character: Character.ID?, for line: Line.ID, source: SpeakerSource) async throws
}
```

## Acceptance tests
- Tagging, adding references (max 6), renaming and deleting work with undo.
- Over-length names and descriptions are rejected in the UI and by the backend.
- Proposed vs user-set Speakers are distinguishable and user choices are never overwritten by later proposals.
