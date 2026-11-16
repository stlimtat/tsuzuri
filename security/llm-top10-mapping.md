# OWASP Top 10 for LLM Applications: controls and tests

_Owner: Lead · Required by `specs/R1/security.md` · Status: M1 skeleton_

> **Verify against the 2026 edition.** This skeleton uses the item list of the 2025 edition (LLM01–LLM10). Update the IDs and names when the 2026 list is confirmed, and keep every item mapped.

Release gate: every row has at least one passing automated test.

| ID | Risk | Controls (where) | Automated tests | Status |
|---|---|---|---|---|
| LLM01 | Prompt injection (direct and indirect) | Fixed, versioned prompt templates; user-derived text (Lines, notes, Cast fields, story summary) inserted only as delimited data; text read from Panels untrusted end to end (Backend, Render Client) | Red-team suite with `Fixtures/golden/poisoned/notes.json` and poisoned Pages | Pending (M3, M5) |
| LLM02 | Sensitive information disclosure | No page content stored server-side; job inputs/outputs deleted on delivery; no user content in logs (Backend) | Log-scrubbing test; retention test on job store | Pending (M3) |
| LLM03 | Supply chain | Dependency allowlist (`security/dependency-allowlist.txt`), lockfiles, secret scan, SAST, pinned CI actions (`.github/workflows/ci.yml`) | `scripts/check-dependencies.sh`, gitleaks, CodeQL on every pull request | **Active (M1)** |
| LLM04 | Data and model poisoning | No training on user data; provider contracts reviewed (Backend, M0 trial) | Provider retention check in M0 report | Pending (M0) |
| LLM05 | Improper output handling | Preparation-LLM output parsed into strict schemas and rejected if invalid; output moderation before use (Backend) | Schema-breaking output cases (`schema-break` entry) | Pending (M3, M5) |
| LLM06 | Excessive agency | AI calls have no tools, no network access, no ability to change accounts or entitlements (Backend) | Contract test: provider requests carry no tool definitions | Pending (M3) |
| LLM07 | System prompt leakage | No secrets in system prompts (Backend) | Leakage probes (`direct-ignore`, `summary-exfil`) | Pending (M5) |
| LLM08 | Vector and embedding weaknesses | Not applicable in R1: no retrieval or embeddings. Re-assess if added | — | N/A (R1) |
| LLM09 | Misinformation | Translations and Speaker proposals are marked by source (`ocrSource`, `translationSource`, `speakerSource` in `ComicStructure`) and user-editable | `ComicStructure` tests: user edits set `.user` sources | Partial (M1) |
| LLM10 | Unbounded consumption | Per-account consumption and rate limits; users pay for every downstream call (Backend, Payments) | Consumption-abuse cases (`consumption` entry); limit tests | Pending (M3, M6) |
