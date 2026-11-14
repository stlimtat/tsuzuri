# Bring-your-own-key is for paying subscribers only, and goes through our backend

Users may supply their own key for a supported video generator, but only as paying subscribers: their key offsets the cost of video generation, while the subscription pays for our backend, maintenance and the Render pipeline (Cast matching, context summaries, prompt building, safety checks). BYOK requests go through our backend, which uses the key for that one request and never stores it; the key lives in the device Keychain. This keeps one pipeline and one security model for everyone, and means we maintain an explicit list of supported video generators.

## Considered Options
- Device calls the provider directly with the user's key: rejected; it bypasses the Render pipeline and safety checks and breaks ADR 0003
- Free BYOK: rejected; it would leave backend and maintenance costs unpaid, and we do not subsidise AI use

## Consequences
- The AI cost of failed or blocked attempts is always borne by the user (their allowance, credits or own key), never by us.
