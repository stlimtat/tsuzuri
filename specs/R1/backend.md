# R1 · Backend and API client

_Location: `/backend` (service) and `BackendClient` (Swift package) · Tier 1 · Depends on: none_

## Purpose
The only component that talks to AI vendors. It authenticates users, checks entitlement, meters consumption, runs vertical OCR and the Render pipeline, and hides providers so they can be swapped on cost (ADR 0003).

## Hosting requirements
The Lead picks the stack in M1 against these requirements:
- HTTPS API with low cold-start latency; async job queue for Renders (minutes-long jobs).
- Temporary object storage with **automatic expiry** for job inputs and outputs.
- A worker that can transcode video (e.g. ffmpeg in a container) to the delivery resolution.
- A small database for accounts, entitlements and usage; secrets manager for vendor keys; APNs for push.
- Example stacks: a serverless API + queue + container worker (e.g. Cloudflare Workers/Queues/R2 + a container service, or Google Cloud Run + Cloud Tasks + Cloud Storage).

## Data kept (and nothing else)
| Data | Retention |
|---|---|
| Apple account ID (from Sign in with Apple), `appAccountToken` | Until account deletion |
| Entitlement (subscription status, credit balance), from App Store Server Notifications V2 and App Store Server API | Until account deletion |
| Usage ledger: consumption units per request (tokens, video seconds, provider, cost), no content | Until account deletion (needed for billing disputes) |
| Job inputs (crops, Lines, Cast data, summary, note) | Deleted when the job finishes or fails |
| Job output video | Deleted when the device confirms download, or after 24 h |
| BYOK keys | **Never stored**; used for one request, excluded from logs |
| Logs | No content, no keys; request IDs, timings, error codes; 30 days |

## API (v1)
| Endpoint | Purpose |
|---|---|
| `POST /v1/auth/apple` | Exchange a Sign in with Apple identity token for a short-lived session token |
| `POST /v1/ocr` | Vertical Bubble crops → text (paid) |
| `POST /v1/renders` | Create a Render job (paid) |
| `GET /v1/renders/{id}` | Job status; signed download URL when ready |
| `POST /v1/renders/{id}/delivered` | Device confirms download → delete output |
| `POST /v1/devices` | Register APNs token |
| `GET /v1/config` | Delivery resolution table, supported providers, limits |
| `POST /v1/appstore/notifications` | App Store Server Notifications V2 receiver |
| `DELETE /v1/account` | Delete account and all server data |

All endpoints except auth and the App Store receiver require a session token. Every paid endpoint checks entitlement **before** calling a vendor.

## Render pipeline (server side)
1. **Validate and moderate** all inputs: sizes, counts (1–10 Panels), note ≤100 chars, Cast fields; moderation of note, Cast names and voice descriptions, and image moderation of Panel crops (including a mandatory block on sexual content involving minors).
2. **Prepare** (LLM step, cost charged to the Render): match Cast references to figures in the Panels; propose Speakers for unassigned Lines; update the story summary; split the clip time across Panels by dialogue length; **build the provider prompt from fixed templates**, inserting Lines, names and descriptions as quoted data fields, never as instructions.
3. **Generate** with the selected provider (or the user's BYOK provider and key), with the model voicing the dialogue in the reading mode's language.
4. **Transcode** to the requested delivery resolution; delete the original.
5. **Notify** the device via APNs; hold the output until delivered or 24 h.
6. **Meter**: record consumption units and the provider's charge, including failed or blocked attempts the provider charged for.

## Providers
- A provider interface per capability (`OCRProvider`, `PreparationLLM`, `VideoProvider`, `ModerationProvider`), each with cost reporting.
- **Two video providers at launch** (M0 winner + alternative); one OCR provider. Prefer providers with zero or minimal input retention and no charge for blocked requests.
- Switching providers is a config change, not an app update.

## Metering and limits
- Allowances, credits and limits are counted in **downstream consumption units** (tokens, video seconds), converted to cost per provider.
- Order of use: subscription allowance → credits → offer to buy credits. BYOK: video cost goes to the user's key; preparation and moderation still use the allowance.
- **Consumption limits** per account (per hour and per day, in units) and request rate limits stop abuse and runaway use; thresholds are config. Users are not shown allowances.

## Acceptance tests
- Contract tests for every endpoint against the `BackendClient` (shared OpenAPI document as source of truth).
- Entitlement: unentitled, expired, refunded and revoked users are refused before any vendor call (App Store sandbox test cases).
- Retention: integration test asserts inputs and outputs are gone after completion / delivery / 24 h; BYOK key never appears in storage or logs.
- Prompt building: poisoned Lines, notes and Cast fields stay inside data fields (template tests + red-team suite, `R1/security.md`).
- Provider swap: switching the default video provider in config works without redeploying the app.
- Load: 50 concurrent Render jobs complete without dropped jobs.
- Account deletion removes all rows and pending jobs within 1 hour.
