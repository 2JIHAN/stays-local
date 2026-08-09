# 006 — link libcurl

**Mechanism.** The app links `/usr/lib/libcurl.4.dylib` and calls `curl_easy_*`. No dynamic loading, no reflection, no trickery: the library is in the link table and the symbols are in the symbol table. This is what an app does when it wants HTTP and is not trying to hide.

The URL is assembled at runtime, so no `http://…` literal survives into the binary. That part is not exotic either — a `snprintf` of the host is enough — and without it layer 3 would catch the case for the wrong reason and hide the actual gap.

**Expected verdict.** `FAIL`.

**Caught by.** Layers 1 and 2, since [`proposals/0002`](../../../proposals/0002-libcurl.md).

**It did not used to be.** When this case was written, all three required layers passed it:

```
1. Linked frameworks    PASS  no CFNetwork or Network.framework
2. Referenced symbols   PASS  no networking symbols referenced
3. Remote addresses     PASS  every remote address is declared [none]
PASS — Bypass case 006 — libcurl meets stays local macos v1
```

Layer 1 matched only `CFNetwork`, `Network.framework` and `libnetwork`; layer 2 matched only Apple's own APIs plus bare `_connect`/`_socket`. Neither named the HTTP library macOS ships in `/usr/lib`. The layers were written against the way a Cocoa app reaches the network and quietly assumed that was the only way.

**Safety.** `192.0.2.1` is TEST-NET-1 (RFC 5737): reserved for documentation, assigned to nobody, routed nowhere. Building the fixture touches no network. Running it attempts a connection that reaches no service, and leaves the socket in `SYN_SENT` long enough for the runtime layer to notice — which is why the case fails layer 4 as well.

**What it does not fix.** The other half of [#11](https://github.com/2JIHAN/stays-local/issues/11) — `syscall(97, …)` for a raw socket — still passes every static layer. Its only import is `_syscall`, which has too many innocent uses to fail on.
