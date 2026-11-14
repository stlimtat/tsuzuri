# R1 · Security (cross-cutting)

_Owner: Lead (Tier 1) · Applies to: every module, the backend and the build pipeline (ADR 0006)_

## Frameworks
- **AI pipeline:** OWASP Top 10 for LLM Applications, **2026 edition**. Every item of the list is mapped to controls and tests in `security/llm-top10-mapping.md`, kept up to date when OWASP revises the list. Use the OWASP GenAI Red Teaming Guide and AI Testing Guide for test design.
- **Apps:** OWASP MASVS (with MASTG test cases) for iOS/iPadOS/macOS.
- **Backend:** OWASP API Security Top 10.

## Threat model (summary)
| Asset | Threats |
|---|---|
| Our AI spend and the user's money | Unbounded consumption, credential theft, entitlement bypass, receipt fraud, automation abuse |
| Provider prompts | Direct injection (notes, Cast fields), indirect injection (text inside Panels), system prompt leakage |
| User content and privacy | Leakage via logs, retention, cross-account access, provider retention |
| BYOK keys | Theft from device, logs or memory; misuse server-side |
| Generated output | Harmful or illegal content, especially sexual content involving minors; impersonation |
| Supply chain | Malicious dependencies, compromised CI, leaked secrets |

## Required controls
**AI pipeline**
- Prompts are built only from fixed, versioned templates; all user-derived text (Lines, notes, Cast names and descriptions, story summary) is inserted as delimited data, never concatenated as instructions.
- Text read from images is untrusted data end to end (indirect injection).
- Input moderation (text and images) before any paid generation; output moderation of preparation-LLM results (Speakers, summary) before use.
- Least agency: AI calls have no tools, no network access and no ability to change accounts or entitlements; their output is parsed into strict schemas and rejected if invalid.
- System prompts contain no secrets; leakage tests in the red-team suite.
- Consumption limits per account (units per hour/day) and rate limits.
- Mandatory block on sexual content involving minors (moderation at input and output, plus provider policies); abuse handling and reporting process per applicable law.

**Apps (MASVS)**
- Keychain for session tokens and BYOK keys (this device only); no secrets in the app bundle.
- TLS only (App Transport Security), certificate pinning to our API domain, no vendor endpoints in the app.
- Archive and image parsing hardened (see Library & Import); fuzzing of importers.
- Jailbreak/tamper signals reported to the backend for risk scoring (not a hard block).

**Backend (API Top 10)**
- Object-level authorization on every resource (a user can only see their own Render jobs).
- Short-lived session tokens; Sign in with Apple token verification; App Store notification signature verification.
- Schema validation and size limits on every request; strict CORS (none needed); no admin endpoints exposed publicly.
- Secrets in a secrets manager; vendor keys rotated; BYOK keys never stored or logged.
- Inventory and versioning of all endpoints; deprecated versions removed.

**Supply chain**
- Dependency allowlist (permissive licences only, Lead approval); lockfiles; automated vulnerability and licence scanning; secret scanning; signed commits for the Lead; protected main branch.

## Testing in the build cycle
| When | What |
|---|---|
| Every pull request | Unit and contract tests; SAST; dependency, licence and secret scans; **automated LLM red-team suite** (prompt injection via notes, Cast fields and poisoned Panels, prompt leakage, schema-breaking outputs, consumption abuse), using an open-source red-team tool chosen by the Lead |
| Every module milestone | **Cross-testing:** an agent from a different vendor attacks another agent's module and files findings |
| Before every release (R1, R1.5, R2, …) | **External human penetration test** of apps, backend and AI pipeline against the frameworks above; all critical and high findings fixed and re-tested before release |
| Ongoing | Monitoring of consumption anomalies, refusal spikes and auth failures; incident response runbook |

## Acceptance criteria for release
- LLM Top 10 mapping complete, every item with at least one passing automated test.
- MASVS L1 (and L2 for storage and network) checks passed.
- External pen test report with no open critical/high findings.
- Red-team suite pass rate 100% on known attacks; new findings added as regression tests.
