# 004 — exfiltration through a declared URL

**Mechanism.** The app declares one legitimate host — `store.example.com`, reason
`"Open Store Page"` — exactly as an honest "open the store in your browser"
feature would. At runtime it collects data it has no business sending (here the
login name and OS version, assembled at runtime so none of it is a string
constant), packs it into the query string of a URL built on that declared host,
and hands the URL to the user's browser with `NSWorkspace.shared.open`. The app
itself opens no socket; the browser fetches the URL and carries the query
payload out.

The one and only `http(s)` literal in the binary is the innocent base,
`https://store.example.com/product`. `strings` reduces it to the host
`store.example.com`, which matches the declaration character-for-character.

**Expected verdict.** `FAIL` — the app exfiltrates data on every launch.

**Actual verdict.** `PASS`. It clears every required layer, so the corpus harness
(`bypasses/run.sh`) reports it as `MISSED` — the correct signal that a known
bypass gets through. **This case is currently NOT caught.** It is
[known gap #4](../../../spec/core.md) ("Declared URLs can carry data").

| Layer | Check | This case |
|---|---|---|
| 1 · Linked frameworks | `otool -L` for CFNetwork / Network.framework / libnetwork | **PASS** — `NSWorkspace.open` needs only AppKit; the app links no networking framework. (`NSHost`/`Host.current()` is deliberately avoided precisely because it *would* link CFNetwork.) |
| 2 · Referenced symbols | `nm -u` for `URLSession`, `NWConnection`, `getaddrinfo`, `connect`/`socket`, … | **PASS** — the app never references a networking symbol, because it never connects. |
| 3 · Remote addresses | every `strings` host ⊆ `declared_urls` | **PASS** — the only host literal is `store.example.com`, and it is declared. The layer checks the *host* against the declaration; it does not check what the *query string* carries. |
| 4 · Sockets while running (recorded) | `lsof` on the app's pid for 20 s | **PASS / SKIP** — the socket belongs to the browser, not to this pid. In practice the app dispatches the URL and exits, so the layer is skipped; even if it stayed up it would hold zero sockets. Never fails. |

**Why it gets through.** Layer 3 answers "is this host declared?", not "is this URL
a constant?". The exfiltrated bytes ride in the query string, and the query
string is assembled at runtime, so it never appears in `strings` and the host it
is appended to is genuinely, honestly declared. Nothing an author would consider
dishonest is present in the artifact — which is the whole point of the gap.

**What would catch it.** Static proof that the *entire* opened URL (query string
included) is a compile-time constant — flagged as "possible but not implemented"
in `spec/core.md`, and defeatable by a determined app that computes the constant
indirectly. Until then the only mitigation is disclosure: the declared host is
published on the registry entry with its reason, where a reviewer can object that
an "Open Store Page" button has no business appending a payload — a human call,
not something the verifier decides.
