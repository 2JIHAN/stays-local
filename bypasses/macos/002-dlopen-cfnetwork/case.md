# 002 — dlopen CFNetwork at runtime

**Mechanism.** The app links no networking framework and names no networking
symbol at build time. At launch it hands the loader a path —
`dlopen("/System/Library/Frameworks/CFNetwork.framework/CFNetwork")` — and looks
its entry points up by string with `dlsym` (`CFStreamCreatePairWithSocketToHost`,
plus `CFReadStreamOpen`/`CFWriteStreamOpen` from CoreFoundation). It then opens a
TCP stream pair and drives the run loop so the connect begins **immediately**.
Nothing that reaches the network exists in the binary's link table or symbol
table; it is all resolved from plain strings after the process is already
running. `NSClassFromString("NSURLSession")` would get to the same place by a
different door.

This is the executable form of `spec/core.md`'s known gap **"Dynamic loading
defeats static linkage checks."**

The destination is `192.0.2.1:80` — TEST-NET-1 (RFC 5737), reserved for
documentation and assigned to no real host, so the fixture reaches no third-party
service. The address is unrouted, so the socket sits in `SYN_SENT` for the whole
window — exactly the state the runtime layer is meant to notice. (Loopback would
be purer but a refused connection closes in microseconds, faster than the layer's
half-second poll, and would prove less than it should.)

**Expected verdict.** `FAIL` — the app reaches the network on every launch.

**Actual status: `caught`, but only by a layer that is not required.** It clears
**all three required layers (1, 2, 3)** — the checks that actually decide a
certification. The only thing that catches it is the **recorded** runtime socket
layer (4), and only because the fixture connects immediately and holds the socket
open across the observation window. `bypasses/run.sh` runs cases with `--runtime`
by default and the CI that issues certifications launches GUI apps, so in practice
the socket is seen and the status is `caught`. That catch is a property of the
environment, not of the required checks — see the caveat below.

## Layer by layer

| Layer | Status | Result | Why |
|---|---|---|---|
| 1 · Linked frameworks | required | **PASS (misses it)** | `otool -L` shows only Foundation/CoreFoundation/libSystem/swift. CFNetwork is never a load command — it arrives through `dlopen` at runtime, which leaves no linkage for the static check to see. |
| 2 · Referenced symbols | required | **PASS (misses it)** | `nm -u` shows no `URLSession`, `CFStream`, `getaddrinfo`, `connect`, `socket`, … The only imports involved are `_dlopen`/`_dlsym`, which are not networking symbols. Every CFNetwork/CoreFoundation function is fetched by name as a string, so none appears as an undefined symbol. |
| 3 · Remote addresses | required | **PASS (misses it)** | No `http(s)://` literal in the binary. The host is the bare string `192.0.2.1` (CFStream takes host + port, no scheme), and the framework paths carry no scheme either, so the `https?://` grep finds nothing. `declared_urls` is empty, as an author claiming "stays local" would leave it. |
| 4 · Sockets while running | recorded | **CATCHES it — when it runs** | `open -a` launches the app; within the first poll `lsof -nP -i -a -p <pid>` shows `TCP …->192.0.2.1:80 (SYN_SENT)`. The fixture connects on launch and sleeps ~30 s so the socket stays visible for the full 20 s window. |

Verified locally: `verify.sh --static` (or no `--runtime`) exits **0** — all three
required layers pass. `verify.sh --runtime` exits **1** on layer 4, with the
`SYN_SENT` socket in the report.

## The catch is a recorded layer, and recorded layers do not always run

Layer 4 is **recorded**, not **required** (`spec/core.md`, "Layer status"): its
result is published but does not by itself decide the verdict, because it cannot
run everywhere. It is skipped whenever the app does not start — a headless runner
with no GUI session. On such a runner layers 1–3 pass and layer 4 never fires, so
**`verify.sh` exits 0 and the bypass succeeds outright**. The same is true of a
deliberate `--static` run.

So `caught` here is contingent on the runtime layer actually running. It holds on
GitHub's `macos-15` runners (which launch GUI apps) and on a developer's Mac; it
does **not** hold on a headless box. The required checks — the ones a certification
is really staked on — never catch this in any environment. That is the point of
the case: an app can pass the load-bearing static layers with room to spare and
still open a socket the moment it runs.

## What would catch it in the required layers

Nothing static and cheap fully closes this. A binary that `dlopen`s a framework by
path and `dlsym`s by string can be spotted by flagging `dlopen`/`dlsym` usage, but
that is heuristic (legitimate apps use them) and defeatable by obfuscating the
path and symbol strings, or by computing them at runtime. The sound fix is to make
a runtime observation **required** rather than recorded — which the scheme cannot
do while headless CI exists, which is exactly why layer 4 is recorded. This case
marks the edge where a static link/symbol scan stops being sufficient.
