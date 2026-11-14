# One monorepo, one Swift package per module, shared model owned by the lead

The app is built by AI agents from different vendors, assigned to modules by cost tier. Each module is its own Swift package in one GitHub monorepo, exposing a published protocol and its own tests; GitHub Actions runs every package's tests on each pull request. Only the lead (the user, with a Tier 1 lead agent) may change the shared domain model and cross-module interfaces, because agents from different vendors drift on shared types fastest. Tier 2–3 pull requests need lead review before merging.

## Considered Options
- One repo per module (rejected: shared types and the glossary would fork)
- No lead, agents negotiate interfaces (rejected: no one owns consistency)
