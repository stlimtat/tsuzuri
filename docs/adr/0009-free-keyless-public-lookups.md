# Free keyless public catalog lookups go straight from the device

This amends ADR 0004. The device may call free public catalogs that need no key and no account, such as Open Library and openBD, for non-AI metadata lookups. It sends only the query: an ISBN, or a title and author. These calls are free to users, cost us nothing and carry no page content, so the "every cloud use is paid" rule doesn't apply to them. They don't go through our backend (ADR 0003), because there is no vendor key to hide and routing them through us would add cost and a privacy surface for nothing.

## Consequences
- Only one module, `BookLookup`, may use the network on the device for this. Every other module keeps its no-networking test.
- Catalog responses are untrusted input: every field is length-capped and stripped of markup before it reaches the UI or an OPF.
- Requests identify the app with `User-Agent: Tsuzuri/<version> (<support email>)`, the email coming from a build setting, so catalogs can contact us before they block us.
- Before the release that ships lookups, the Lead confirms that each catalog's terms allow use from a paid app.
- Any catalog that needs a key or charges per call is not covered by this ADR. It goes through the backend and is paid, as ADR 0004 says.
