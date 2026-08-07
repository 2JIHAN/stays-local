# Bypasses

A badge is worth what the attacks it survives are worth. This is the catalogue of ways an app can reach the network while passing some or all layers.

It is public on purpose. A scheme that hides how it can be fooled is asking to be trusted rather than earning it, and none of these are hard to rediscover. Published, they become a test suite that any verifier — including ones we did not write — can be run against.

## Running it

```bash
./bypasses/run.sh          # every platform that has a verifier
./bypasses/run.sh macos
```

Cases are expected to **fail** verification. A case that passes means the verifier missed a known bypass, and the harness reports it as `MISSED`.

Every verifier must catch every executable case for its platform before it can be merged.

## The cases

| Case | Mechanism | Status |
|---|---|---|
| [macos/001](macos/001-direct-urlsession/) | Direct `URLSession` reference | **caught** — layers 1, 2, 3 |
| macos/002 | `dlopen` CFNetwork and resolve symbols at runtime | **open** — static layers miss it; the runtime layer catches it only if it connects during the window |
| macos/003 | Shell out to `curl` via `Process` | **open** — nothing in the binary references networking |
| macos/004 | Exfiltrate through a declared URL's query string | **open** — this is the [known gap](../spec/core.md) in the declared-address layer |
| macos/005 | XPC to a helper that has network access | **open** — the helper is outside the bundle we check |

`caught` means an executable case exists and the verifier fails it. `open` means the mechanism is written down and not yet implemented as a case, or implemented and not yet caught. Both are honest states; a case that exists and is not caught is more useful than one nobody wrote.

## Adding a case

1. `bypasses/<platform>/<nnn>-<short-name>/`
2. A minimal app that reaches the network, plus `build.sh` writing the bundle into `$1`.
3. `stays-local.json` with the manifest, `declared_urls` reflecting what an author trying to sneak this through would plausibly declare.
4. `case.md` — the mechanism, expected verdict, and which layers should catch it.
5. Run `./bypasses/run.sh <platform>`.

If your case is **caught**, it becomes a regression test and can go straight into a pull request.

If your case is **not caught**, it is a working bypass against every currently certified app. Read [SECURITY.md](../SECURITY.md) before opening it in public.

Cases that are documented but not executable — like 002 through 005 above — are still worth adding as a `case.md` with no code. Writing down the mechanism precisely is most of the work.
