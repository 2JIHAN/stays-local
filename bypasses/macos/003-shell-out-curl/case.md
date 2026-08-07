# 003 — shell out to curl

**Mechanism.** The app never calls a networking API. It launches `/usr/bin/curl`
as a child process (Foundation's `Process`/`NSTask`, backed by `posix_spawn`) and
lets that binary carry the data off the machine. `/usr/bin/nc` would work the same
way. The destination is passed as a curl argument rather than embedded as an
`http://` literal, so it is not even a scheme-prefixed string in the app's binary.

This is the boundary case for the whole scheme. The badge's claim is *"the app's
shipped code contains no way to reach the network"* — and that claim is literally
true here. The network access lives in `/usr/bin/curl`, which is not part of the
app's build. `spec/core.md` names this in "What the badge does not claim": *"curl
in a script the app runs is invisible to a binary scan."* This case makes that
sentence executable.

**Expected verdict.** `FAIL`. The app exfiltrates data.

**Actual verdict today.** `PASS`. **Nothing catches it.** The corpus harness
(`bypasses/run.sh`) reports it as `MISSED`, which is the correct and intended
signal for a working, uncaught bypass — not a bug in this fixture.

## Layer by layer

| Layer | Status | Result | Why |
|---|---|---|---|
| 1. Linked frameworks | required | **passes** | Binary links only Foundation/libSystem/swift. No `CFNetwork`, no `Network.framework` — `Process` needs none of them (`otool -L` is clean). |
| 2. Referenced symbols | required | **passes** | `nm -u` shows no `URLSession`, `getaddrinfo`, `connect`, `socket`, etc. Spawning a child uses `posix_spawn`, which is not a networking symbol. |
| 3. Remote addresses | required | **passes** | No `https?://` literal in the binary. curl defaults the scheme to `http`, so a bare host argument reaches the network without ever appearing as a URL string. `declared_urls` is empty, as an author claiming "stays local" would leave it. |
| 4. Sockets while running | recorded | **passes (misses it)** | The layer runs `lsof -nP -i -a -p <APP_PID>`. The socket belongs to the **curl child's** pid, not the app's, so watching the app's pid sees nothing. |

Layers 1–3 are not "worked around" here — they are simply out of scope. There is
genuinely no networking in the artifact they inspect. Layer 4 is the only layer
that observes behavior instead of the binary, and it is the one that could catch
this — but it looks at the wrong pid.

### Verified empirically

The parent process holds zero sockets while its curl child holds the connection:

```
demo(parent) pid=8421   curl(child) pid=8462
--- lsof -i on PARENT (8421) ---      (none)
--- lsof -i on CHILD  (8462) ---
curl  8462  ...  TCP 192.168.45.237:49956->10.255.255.1:80 (SYN_SENT)
```

Layer 4 as written passes exactly the pid (8421) that has nothing on it.

## What a fix would look like

Layer 4 would have to watch the **whole process tree the app spawns**, not just
its main pid:

- After launch, enumerate descendants (`pgrep -P`, recursively, or a `dtrace`/
  ` launchd` subtree observer) and run `lsof -i` against every pid in the tree,
  re-sampling as new children appear.
- Any socket opened by any descendant — `curl`, `nc`, a spawned shell, an
  interpreter — counts as the app reaching the network.

**This is not implemented.** It also does not fully close the mechanism: an app
can hand work to a process it does *not* parent (launch an agent, poke an already-
running daemon, or route through `open`/`launchctl`), which is the sibling gap
tracked as `bypasses/macos/005` (XPC/helper). Process-tree watching raises the
cost of the curl-shellout trick specifically; it does not make the runtime layer
sound. The static layers cannot catch this at all, because by construction there
is nothing networking-related in the artifact to find.

This case is worth keeping precisely because it does not have a clean fix. It
marks the edge of what a binary-plus-single-pid check can prove.
