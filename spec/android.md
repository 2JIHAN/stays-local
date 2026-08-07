# stays local — Android, spec v1 (draft)

**Status: draft. No verifier yet — [help wanted](https://github.com/2JIHAN/stays-local/labels/verifier).**

Read `spec/core.md` first.

Android is the strongest platform for this scheme, and worth doing first. On macOS we infer "cannot reach the network" from what the binary links. On Android the operating system enforces it: without `android.permission.INTERNET`, `socket()` returns `EACCES`. The badge stops being an inference and becomes a statement about a sandbox the OS applies.

## Subject

An `.apk` built from public source. If the project ships an `.aab`, the manifest must declare a build command that produces a universal APK.

## Layers

### 1. No INTERNET permission — required

The **merged** manifest declares neither `android.permission.INTERNET` nor `android.permission.ACCESS_NETWORK_STATE`.

Merged, not the app module's `AndroidManifest.xml` — a dependency can add a permission through manifest merging, and that is exactly the case worth catching. Read it from the built APK (`aapt2 dump permissions`), never from source, so merging has already happened.

### 2. No networking APIs in the code — required

No DEX in the APK references `java.net.Socket`, `java.net.URL.openConnection`, `HttpURLConnection`, `okhttp3`, `retrofit2`, `android.webkit.WebView`, or `java.net.DatagramSocket`.

Layer 1 already makes these fail at runtime, so this layer is about intent: code that tries to open a socket wants network access, and an app that wants it should not carry this badge. It also catches an app that plans to add the permission later.

Native libraries in `lib/` must be checked too, for `socket`, `connect`, and `getaddrinfo` in their dynamic symbol tables.

### 3. Remote addresses — required

Same rule as every platform: every `http://` or `https://` string in the DEX, resources, and native libraries must be declared. `android.intent.action.VIEW` to a browser is the legitimate case.

### 4. Sockets while running — recorded

Install on an emulator, exercise the app, and read `/proc/net/tcp` and `/proc/net/tcp6` filtered to the app's UID. Zero entries.

## Open questions for whoever implements this

These are genuine design decisions, not busywork. Argue for an answer in the tracking issue.

- **WebView.** A `WebView` cannot load remote content without INTERNET, but it can load local assets. Ban it outright, or allow it when layer 1 passes?
- **Ads and analytics SDKs.** They pull the INTERNET permission through manifest merging, so layer 1 already rejects them. Worth stating explicitly so nobody is surprised.
- **`aapt2` vs parsing the binary XML directly.** Depending on the Android SDK in CI is heavy; a small binary-XML parser has no dependencies but is code we then maintain.
- **Reproducibility.** Gradle builds pull dependencies from the network at build time. That is fine — the *build* may use the network, the *app* may not — but the verifier must not confuse the two.

## Prior art worth reading

- F-Droid's anti-features and its `NonFreeNet` flag
- Exodus Privacy's tracker detection in APKs
