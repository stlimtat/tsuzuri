# R1 · Payments

_Package: `Payments` · Tier 2 · Depends on: Backend client_

## Purpose
Sell the subscription and credit packs with StoreKit 2, and keep the backend's entitlement in step.

## Products
| Product | Type | Notes |
|---|---|---|
| Subscription (monthly, yearly) | Auto-renewable, one subscription group | Unlocks vertical OCR and Renders with internal allowances; required for BYOK |
| Credit packs (2–3 sizes) | Consumable | Used after the allowance; priced by the formula in the overview §10 |

Prices are set after M0. No free trial (cloud use is never subsidised); an optional paid introductory offer (discounted first period) is allowed.

## Requirements
1. StoreKit 2 purchase, restore, and transaction listener at app launch.
2. `appAccountToken` = a UUID derived from the backend account, so the App Store Server Notifications V2 tie purchases to the account.
3. The backend is the source of truth for entitlement; the app shows state from `GET /v1/config` + account status, never trusts local state alone for paid calls.
4. Allowances are **not shown**. When a paid action is refused for lack of allowance, show "You've used this month's included usage" with credit pack options.
5. **BYOK:** available only with an active subscription. The user picks a supported provider (from `/v1/config`) and pastes a key; the key is stored in the Keychain (this device only, not synced) and sent per Render request.
6. Handle refunds, revocations, billing retry and grace period per Apple's guidance (via backend notifications).
7. Join the App Store Small Business Program (operational task, not code).

## Acceptance tests
- Sandbox: purchase, renew, cancel, refund, revoke, restore on a new device, family sharing off.
- Credits are consumed only after the allowance (backend test) and never go negative.
- BYOK entry hidden without an active subscription; key never leaves the Keychain except in a Render request.
- Out-of-allowance flow shows credit packs and completes a paid action after purchase.
