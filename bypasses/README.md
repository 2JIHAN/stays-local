# Bypasses

A badge is worth what the attacks it survives are worth. This is the catalogue of ways an app can reach the network while passing some or all layers.

It is public on purpose. A scheme that hides how it can be fooled is asking to be trusted rather than earning it, and none of these are hard to rediscover. Published, they become a test suite that any verifier — including ones we did not write — can be run against.

## Running it

```bash
./bypasses/run.sh              # every platform that has a verifier
./bypasses/run.sh macos
./bypasses/run.sh macos --static   # skip the runtime layer; faster, proves less
```

Cases run the way a certification runs, runtime layer included, because some bypasses are only caught there.

Each case declares what is expected of it today in a file named `expected`:

| `expected` | Meaning |
|---|---|
| `caught` | The verifier fails this case, and must keep doing so |
| `uncaught` | The verifier passes it — a known, documented limit |

**Only a regression fails the run**: a `caught` case that stops being caught. A case that is known-uncaught and stays uncaught is reported and tolerated.

That asymmetry is deliberate. If adding a case nothing catches turned CI red, nobody would add one, and this catalogue would quietly become a list of problems we had already solved — which is the opposite of its purpose. A case that starts being caught is reported as `IMPROVED`, and its `expected` file should be updated in the same pull request as the verifier change that earned it.

## The cases

| Case | Mechanism | Status | Caught by |
|---|---|---|---|
| [macos/001](macos/001-direct-urlsession/) | Direct `URLSession` reference | **caught** | Layers 1, 2, 3 |
| [macos/002](macos/002-dlopen-cfnetwork/) | `dlopen` CFNetwork, resolve symbols at runtime | **caught** | Layer 4 only — and layer 4 is *recorded*, not required |
| [macos/003](macos/003-shell-out-curl/) | Shell out to `curl` via `Process` | **uncaught** | Nothing. The socket belongs to the child process |
| [macos/004](macos/004-declared-url-exfiltration/) | Data in a declared URL's query string | **uncaught** | Nothing. The [known gap](../spec/core.md#known-gaps) |
| [macos/005](macos/005-xpc-helper/) | XPC to a helper with network access | **uncaught** | Nothing. The helper is outside the bundle |

Two more were found by an adversarial review before the v0.3.0 announcement and are not in the table because nobody has written them as cases yet — [#11](https://github.com/2JIHAN/stays-local/issues/11): linking `libcurl` directly, and calling `syscall(97, …)` for a raw socket. Both pass every layer, and neither needs dynamic loading or any trickery. Writing them up as cases is a good contribution.

Read the table as the honest statement of what a macOS badge is worth: **three of five written cases currently succeed, and at least two more mechanisms are known and uncaptured.** Two of the three are inherent to scanning one process's binary; the third is a gap in a layer we designed. Case 002 is worth singling out — it is caught only by the recorded layer, so on a runner where the app cannot launch, that bypass succeeds too.

Fixtures never contact a real host. They target RFC 2606 `.invalid` / `example.com` names, or RFC 5737 `192.0.2.1`, which is reserved and routed nowhere. A catalogue of attacks that performs the attack on a third party would not be a test suite.

## Adding a case

1. `bypasses/<platform>/<nnn>-<short-name>/`
2. A minimal app that reaches the network, plus `build.sh` writing the bundle into `$1`.
3. `stays-local.json` with the manifest, `declared_urls` reflecting what an author trying to sneak this through would plausibly declare.
4. `case.md` — the mechanism, expected verdict, and which layers should catch it.
5. `expected` — one word, `caught` or `uncaught`. The harness refuses a case without one, because nobody can tell a regression from a known limit otherwise.
6. Run `./bypasses/run.sh <platform>`.

Your fixture must not contact a real host, and must not disturb the machine running it — case 004 gates its browser launch behind `STAYS_LOCAL_DEMO=1` for that reason.

If your case is **caught**, it becomes a regression test and can go straight into a pull request.

If your case is **not caught**, it is a working bypass against every currently certified app. Read [SECURITY.md](../SECURITY.md) before opening it in public.

Cases that are documented but not executable — like 002 through 005 above — are still worth adding as a `case.md` with no code. Writing down the mechanism precisely is most of the work.
