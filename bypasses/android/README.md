# Android bypasses

See [`../README.md`](../README.md) for how the corpus works and what `expected` means.

| Case | Mechanism | Status | Caught by |
|---|---|---|---|
| [001](001-internet-permission/) | Declares `INTERNET`, uses `Socket`/`WebView`/`HttpURLConnection` | **caught** | Layers 1, 2, 3 independently |

## Wanted

Mechanisms named in [`spec/android.md`](../../spec/android.md) that deserve a case. The first three are the ones most likely to matter:

- **Merged permission.** The app module's manifest is clean; a dependency AAR declares `INTERNET`, and manifest merging puts it in the built APK. This is the case that justifies layer 1 reading the artifact rather than the source, and it is the one case in this corpus that needs Gradle, because `aapt2` has no merger.
- **`.so` outside `lib/`.** A native library in `assets/`, loaded with `System.load`, walks past any scan that only looks in `lib/`. Rename it to `.dat` and an extension-based scan misses it too — which is why the verifier runs `file` over everything.
- **`android.net.LocalSocket`.** Unix-domain sockets need no `INTERNET` permission at all. They cannot reach the network alone, so the verifier reports rather than fails on them, but they are the clean route to the "IPC to another process" gap in [`spec/core.md`](../../spec/core.md).
- **R8-renamed HTTP client.** Prove that a minified OkHttp survives a package-name grep, so nobody is tempted to make that grep a required rule.
