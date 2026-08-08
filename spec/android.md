# stays local — Android, spec v1

**Status: stable.** Verifier: `verifiers/android/verify.sh`.

Read `spec/core.md` first — the claim, the gaps, and the manifest live there.

Android is the strongest platform this scheme covers. On macOS we infer "cannot reach the network" from the symbols a binary names. On Android the operating system enforces it: without `android.permission.INTERNET`, `socket()` returns `EACCES`. The badge stops being an inference and becomes a statement about a sandbox the OS applies.

## Subject

An `.apk` built from public source. A project that ships an `.aab` must declare a build command that produces a universal APK; the verifier does not convert one.

## Layers

### 1. No INTERNET permission — required

The APK's manifest declares neither `android.permission.INTERNET` nor `android.permission.ACCESS_NETWORK_STATE`.

Read from the **built APK**, never from source, so manifest merging has already happened — a dependency can add a permission the app module never wrote, and that is exactly the case worth catching. This is why the check is post-build, and it is the most valuable property of the Android layers.

Three details that a naive implementation gets wrong:

| Trap | What happens |
|---|---|
| `aapt dump badging` / `apkanalyzer manifest permissions` | Both **invent** permissions. On a manifest with no `<uses-sdk>` they report `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE` and `READ_PHONE_STATE` as `uses-implied-permission`. Use `aapt2 dump permissions`, which never does |
| `uses-permission-sdk-23` | A separate element that requests the same permission. A pattern anchored to `uses-permission:` misses it entirely |
| `android:maxSdkVersion` | Appends to the line, so an end-anchored match fails |

Match the permission *name* on any `uses-permission*` line. Do not match `permission:` — that is the app *defining* a permission, not requesting one. A manifest the tool cannot read is a failure, not a skip: a duplicate-entry APK makes `aapt2` exit non-zero, and that is precisely the artifact that must not pass.

### 2. No networking APIs in the code — required

Layer 1 already makes these fail at runtime, so this layer is about intent: code that tries to open a socket wants network access, and an app that wants it should not carry this badge. It also catches an app that plans to add the permission in the next release.

Match on DEX type and method references, not on `strings`. A string match cannot tell a constant-pool descriptor from an app that merely logs the words "java.net.Socket".

**Class references — fail on any.** These survive R8, because R8 cannot rename classes it does not own:

`java.net.Socket`, `ServerSocket`, `DatagramSocket`, `MulticastSocket`, `SocketImpl`, `DatagramSocketImpl`, `HttpURLConnection`, `URLConnection`, `InetAddress`, `InetSocketAddress`, `NetworkInterface`, `ProxySelector`; `javax.net.SocketFactory`, `javax.net.ssl.SSLSocket`, `SSLSocketFactory`, `HttpsURLConnection`; `java.nio.channels.SocketChannel`, `ServerSocketChannel`, `DatagramChannel`; `android.webkit.WebView`, `WebViewClient`; `android.net.ConnectivityManager`, `android.net.Network`; anything under `org.apache.http.`

**Method references — fail on any.** `java.net.URL` and `URI` construct and parse without touching the network; these are the network:

`URL.openConnection`, `URL.openStream`, `URL.getContent`

**Never match on these.** They are local parsing and error types, observed in innocent apps, and a false positive here would discredit the whole scheme faster than a missed bypass:

`java.net.URI`, `MalformedURLException`, `UnknownHostException`, `SocketException`, `BindException`, `SocketTimeoutException`, `URISyntaxException`, `URLEncoder`, `URLDecoder`

**Report but do not fail** on `okhttp3`, `okio`, `retrofit2`, `com.squareup.okhttp`, `org.apache.hc`, `com.android.volley`, `io.ktor`, `io.grpc`, `com.google.android.gms` — R8 renames library packages, so their absence proves nothing and their presence is a signal, not a verdict.

Native libraries are checked in the same pass: no `.so` anywhere in the APK may import `socket`, `connect`, `bind`, `getaddrinfo`, `gethostbyname`, `send`, `recv`, or their relatives. Match whole symbol names after stripping the `@LIBC` version tag — `connect` as a substring hits `dbus_connect` and `sqlite3_connect`. Look outside `lib/` too: a `.so` in `assets/` loaded with `System.load` is a trivial way past a `lib/`-only scan, and an ELF renamed to `.dat` is the same trick with less typing.

#### WebView

`android.webkit.WebView` fails this layer. Without INTERNET a WebView cannot fetch remote content, so layer 1 already neutralises it — which means banning it costs an author nothing they can actually use, while allowing it would make this layer's stated purpose incoherent. The honest consequence: an app that renders local HTML has no way to keep this badge, and should ship a native UI. That trade-off is written here so nobody meets it as an ambush.

### 3. Remote addresses — required

Same rule as every platform, but Android keeps strings in four places with three encodings, and a verbatim port of the macOS layer finds almost none of them:

| Location | Extractor |
|---|---|
| `classes*.dex` | `strings -a` (MUTF-8) |
| `resources.arsc` | `aapt2 dump strings` (UTF-8) |
| `AndroidManifest.xml`, compiled `res/**/*.xml` | `aapt2 dump xmlstrings` (UTF-16 — plain `strings` returns garbage) |
| `lib/**/*.so`, `assets/**` | `strings -a` |

Toolchain noise must be excluded or the layer is unusable: every `AndroidManifest.xml` contains `schemas.android.com`, and every NDK-built `.so` carries `android.googlesource.com` in `.comment`. The verifier keeps that exclusion list in one named constant, so what is being ignored is reviewable rather than scattered through the code.

### 4. Sockets while running — conditional

Install on an emulator, exercise the app, and read `/proc/net/tcp` and `/proc/net/tcp6` filtered to the app's UID. Zero entries.

Conditional: when the emulator runs, this layer decides. The emulator is the part that flakes, so a run without one records a skip rather than a pass.

## Toolchain

Everything needed is preinstalled on GitHub's `ubuntu-latest`: build-tools (`aapt2`, `d8`, `zipalign`, `apksigner`), `cmdline-tools`, platforms, NDK, JDK, and binutils (`nm`, `readelf`, `strings`).

None of it is on `PATH`. The SDK install script sets `ANDROID_HOME` and `ANDROID_SDK_ROOT` and nothing else, so every tool has to be resolved through `$ANDROID_HOME` with a version glob — never a pinned version, because `ubuntu-latest` carries build-tools 34 through 37 while `macos-15` starts at 35.

## Fixtures

Bypass cases build with `aapt2 link` + `javac` + `d8` directly. No Gradle, no dependencies, no network, about 1.5 seconds and an 8 KB APK. Gradle is reserved for the one case that actually needs it — proving that manifest merging pulls in a permission the app module never declared, which `aapt2` has no merger for.

`spec/core.md` already licenses that split: the build may use the network, the app may not. The verifier cannot conflate them, because it never inspects the build — only the artifact.

## Bypasses

Tracked in `bypasses/android/`. `android.net.LocalSocket` is worth knowing about: Unix-domain sockets need no INTERNET permission and are the clean route to the "IPC to another process" gap in `spec/core.md`. It cannot reach the network by itself, so it is reported as a note rather than failed, and it has a case.
