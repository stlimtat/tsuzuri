# The app talks only to our backend, which hides the AI provider

All cloud requests (vertical-text OCR and Renders) go through our own backend, never directly to an AI vendor. The backend authenticates users with Sign in with Apple, checks their paid entitlement, meters usage, and stores no page images or text after a request completes. This lets us swap or mix providers on cost and accuracy without an App Store update, and keeps vendor API keys out of the app.

## Consequences
- The backend is on the critical path for every paid feature; its availability is a launch requirement.
- Account deletion must be offered in-app (Sign in with Apple accounts).
