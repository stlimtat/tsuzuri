# OWASP Top 10 for LLM Applications: controls and tests

_Owner: Lead · Required by `specs/R1/security.md` · Status: M1 skeleton_

> **Edition: 2026** (LLM01:2026–LLM10:2026), from [OWASP GenAI LLM Top 10 2026](https://genai.owasp.org/resource/owasp-genai-llm-top-10-2026/), published August 2026. It replaces the 2025 list. Notable changes: Excessive Agency rose to LLM03, Improper Output Handling fell to LLM10, and System Prompt Leakage became Hidden Context Exposure (LLM08). Keep every item mapped when OWASP revises the list.

Release gate: every row has at least one passing automated test.

| ID | Risk | Controls (where) | Automated tests | Status |
|---|---|---|---|---|
| LLM01:2026 | Prompt injection (direct, indirect and cross-modal) | Fixed, versioned prompt templates; user-derived text (Lines, notes, Cast fields, story summary) inserted only as delimited data; text read from Panels untrusted end to end, including text inside Page and Panel images sent to models (Backend, Render Client) | Red-team suite with `Fixtures/golden/poisoned/notes.json` (direct) and, for indirect injection, the poisoned golden Pages: every Page in `Fixtures/golden/manifest.json` with the poisoned-text feature (`Fixtures/golden/pages/<id>.png`; Bubbles flagged poisoned in `Fixtures/golden/ground-truth/pages/<id>.json`, at least two Pages) | Pending (M3, M5) |
| LLM02:2026 | Sensitive information disclosure | No page content stored server-side; job inputs/outputs deleted on delivery; no user content in logs (Backend) | Log-scrubbing test; retention test on job store | Pending (M3) |
| LLM03:2026 | Excessive agency | AI calls have no tools, no network access, no ability to change accounts or entitlements (Backend) | Contract test: provider requests carry no tool definitions | Pending (M3) |
| LLM04:2026 | Supply chain | Dependency allowlist (`security/dependency-allowlist.txt`), lockfiles, secret scan, SAST, pinned CI actions (`.github/workflows/ci.yml`); providers chosen in M0 by contract, models used only through their APIs, never downloaded | `scripts/check-dependencies.sh`, gitleaks, CodeQL on every pull request | **Active (M1)** |
| LLM05:2026 | Data and model poisoning | No training or fine-tuning on user data; provider contracts reviewed (Backend, M0 trial) | Provider retention check in M0 report | Pending (M0) |
| LLM06:2026 | Unbounded consumption | Per-account consumption and rate limits; users pay for every downstream call (Backend, Payments) | Consumption-abuse cases (`consumption` entry); limit tests | Pending (M3, M6) |
| LLM07:2026 | Misinformation | Translations and Speaker proposals are marked by source (`ocrSource`, `translationSource`, `speakerSource` in `ComicStructure`) and user-editable | `ComicStructure` tests: user edits set `.user` sources | Partial (M1) |
| LLM08:2026 | Hidden context exposure | No secrets, credentials or entitlement logic in system prompts or other hidden context; hidden context is never a security boundary, authorization is enforced in Backend code (Backend) | Leakage probes (`direct-ignore`, `summary-exfil`) | Pending (M5) |
| LLM09:2026 | Vector and embedding weaknesses | Not applicable in R1: no retrieval or embeddings. Re-assess if added | — | N/A (R1) |
| LLM10:2026 | Improper output handling | Preparation-LLM output parsed into strict schemas and rejected if invalid; output moderation before use; no model-generated code is executed (Backend) | Schema-breaking output cases (`schema-break` entry) | Pending (M3, M5) |
