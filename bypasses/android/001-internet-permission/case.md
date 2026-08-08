# android/001 — INTERNET permission

**Mechanism.** The obvious one, and the floor for any Android verifier. The app declares `android.permission.INTERNET` and `ACCESS_NETWORK_STATE`, constructs a `WebView`, opens an `HttpURLConnection` to a host it never declared, and opens a raw `Socket`.

**Expected verdict.** `FAIL`.

**Caught by.** All three required layers, independently:

| Layer | What it sees |
|---|---|
| 1 — permissions | `uses-permission: android.permission.INTERNET` in the built manifest |
| 2 — code | `Landroid/webkit/WebView;`, `Ljava/net/Socket;`, `Ljava/net/HttpURLConnection;`, `Ljava/net/URL;->openConnection` |
| 3 — addresses | `telemetry.example.com`, undeclared |

Being caught three times over is the point: this is the smoke test that proves the layers are wired up at all, so a single bug cannot make it quietly pass.

**Safety.** `telemetry.example.com` is under RFC 2606's reserved `example.com`, and the socket target is RFC 1918 `10.0.0.1`. Building the fixture touches no network; running it would reach nothing.

**Build.** `aapt2 link` + `javac` + `d8`, no Gradle and no dependencies — about a second and a 2 KB APK.
