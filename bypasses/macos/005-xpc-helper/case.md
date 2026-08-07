# 005 — XPC to a helper outside the bundle

**Mechanism.** The app never calls a networking API. It opens an
`NSXPCConnection` to a **mach service** — `local.stays.case005.helper` — vended by
a *separate* process, and sends its payload over that connection. The other
process (`helper/`) is the one with network access: it holds the `URLSession`,
the `CFNetwork` link, and the remote address, and it POSTs the data out. That
process is installed **outside** `Case005.app` — as a per-user LaunchAgent that
launchd on-demand-launches when the app connects — so it is never part of the
bundle the verifier builds and scans.

XPC rides on **mach ports**, not BSD sockets, so the connection itself is
invisible to a socket scan of the app, and `NSXPCConnection` matches none of the
networking symbol patterns. The app's shipped binary is genuinely clean; the
network access lives in a binary that was never submitted for certification.

This is the sibling of `003` (shell-out) taken one step further: `003` hands work
to a child process the app *parents* (catchable, in principle, by watching the
process tree); `005` hands work to a process the app does **not** parent — an
already-registered agent reached by name — which no process-tree walk from the
app's pid can find.

**Expected verdict.** `FAIL` — the app causes data to leave the machine.

**Actual verdict today.** `PASS`. It clears every required layer, so the corpus
harness (`bypasses/run.sh`) records it as `uncaught` — the correct, intended
signal for a working, undocumented-to-the-verifier bypass, not a bug in this
fixture. This is [bypass macos/005 in the catalogue](../README.md) and is named in
`spec/core.md` under "What the badge does not claim" (*"IPC to another process:
the app can ask a service that does have network access"*). **It is currently NOT
caught.**

## Layer by layer

| Layer | Status | Result | Why |
|---|---|---|---|
| 1. Linked frameworks | required | **passes** | The app links only Foundation / libSystem / swift (incl. `libswiftXPC`, weak). `NSXPCConnection` needs no `CFNetwork` or `Network.framework`, so `otool -L` is clean. |
| 2. Referenced symbols | required | **passes** | `nm -u` shows `_OBJC_CLASS_$_NSXPCConnection` / `_OBJC_CLASS_$_NSXPCInterface` and `xpc_*`, none of which match the patterns (`urlsession`, `nwconnection`, `getaddrinfo`, `_connect$`, `_socket$`, …). XPC uses mach messaging, not `connect`/`socket`. |
| 3. Remote addresses | required | **passes** | The app carries no `http(s)://` literal — the URL lives in the helper. `strings` finds only the mach-service name `local.stays.case005.helper`, which is not scheme-prefixed. `declared_urls` is empty, as an author claiming "stays local" would leave it. |
| 4. Sockets while running | recorded | **passes (misses it)** | `lsof -nP -i -a -p <APP_PID>` watches only the app's pid, which holds zero sockets. The socket belongs to the **helper's** pid — a different process launchd started — so watching the app's pid, or even its whole child tree, sees nothing. |

Layers 1–3 are not "worked around": there is genuinely nothing networking-related
in the artifact they inspect. Layer 4 is the only behavioral layer and the only
one that could catch this, and it looks at the wrong pid — and unlike `003`, the
right pid is not even a descendant of the app.

### Verified empirically

Built through the verifier exactly as a certification runs (`./verify.sh .
--runtime`, manifest copied to the repo root the way `bypasses/run.sh` does it):

```
1. Linked frameworks (required)   PASS  no CFNetwork or Network.framework
2. Referenced symbols (required)  PASS  no networking symbols referenced
3. Remote addresses (required)    PASS  every remote address is declared [none]
4. Sockets while running          PASS  no sockets over a 20-second run
PASS — Bypass case 005 ... meets stays local macos v1
```

The out-of-bundle helper (`helper/`), built on its own, is the mirror image — it
fails all three static layers, which is exactly why it is kept out of the bundle:

```
otool -L   → .../CFNetwork.framework/.../CFNetwork
nm -u      → _OBJC_CLASS_$_NSURLSession
strings    → https://exfil.invalid
```

## Files

| Path | Role | In the scanned bundle? |
|---|---|---|
| `Sources/main.swift` | The app: opens the XPC connection, sends the payload. Clean. | **yes** — this is `Case005.app` |
| `helper/Sources/main.swift` | The helper: vends the mach service, does the `URLSession` POST. Dirty. | **no** — installed separately |
| `helper/local.stays.case005.helper.plist` | LaunchAgent that registers the mach service for on-demand launch. | **no** |
| `helper/build.sh` | Builds the helper and documents the (optional, system-mutating) install to make the bypass live end-to-end. | not run by the verifier |

`build.sh` (this directory) builds only the app into the bundle. To exercise the
full mechanism end-to-end, build and install the helper as described in
`helper/build.sh` — a step this fixture deliberately keeps separate, because
installing a second process is the awkward, out-of-bundle part that is the whole
point of the case.

## What a fix would look like

No layer that scans *this bundle* can catch this, by construction — the offending
code is not in the bundle. Candidate mitigations, all outside the current spec:

- **Declare and scan helpers.** Require the manifest to enumerate every mach
  service / helper the app talks to (as `SMPrivilegedExecutables`-style
  disclosure), then verify those helper binaries too. Catches disclosed helpers;
  an undisclosed one — a service registered by some *other* installed app that
  this app merely knows the name of — is still reachable and still invisible.
- **System-wide runtime capture.** Observe network egress at the machine level
  (a filtering `NEFilterDataProvider`, `pf`/pfctl logging, an eBPF-like tap) for
  the whole session and attribute connections to whatever process opened them,
  rather than watching one pid. This is a fundamentally different and much heavier
  verifier than "scan a bundle," and it moves the claim from *"the shipped code
  cannot reach the network"* to *"nothing reached the network while we watched,"*
  which is a weaker and harder-to-reproduce statement.

Neither is implemented. The honest position is the one `spec/core.md` already
takes: the badge certifies **the app's own shipped code**, and IPC to a
network-capable process it does not contain is explicitly out of that claim. This
case makes that sentence executable, and keeps a runnable demonstration that the
verifier passes such an app.
