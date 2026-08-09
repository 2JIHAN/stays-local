# Proposal: layer 1 and layer 2 must name the HTTP libraries macOS ships

| | |
|---|---|
| Status | accepted |
| Platforms | macos |
| Author | @2JIHAN |
| Opened | 2026-08-09 |

## What a badge claimed

That an app carrying it "contains no way to reach the network".

## What was wrong with it

An app could link `/usr/lib/libcurl.4.dylib`, call `curl_easy_perform`, and pass every required layer. Demonstrated by [`bypasses/macos/006-libcurl`](../bypasses/macos/006-libcurl/), which did exactly that and was certified:

```
1. Linked frameworks    PASS  no CFNetwork or Network.framework
2. Referenced symbols   PASS  no networking symbols referenced
3. Remote addresses     PASS  every remote address is declared [none]
PASS
```

Layer 1 matched `CFNetwork|/Network\.framework|libnetwork`. Layer 2 matched Apple's own APIs plus bare `_connect`/`_socket`. Both were written against the way a Cocoa app reaches the network, and treated that as the only way — while macOS ships a general-purpose HTTP client in `/usr/lib` that any binary can link with `-lcurl`.

This was not dynamic loading or any documented gap. It was ordinary, statically linked network access that the layers did not look for.

## The change

Both patterns move into named lists at the top of the verifier, so what counts as networking can be reviewed as a list rather than reconstructed from inside two greps.

**Layer 1** additionally fails on `libcurl`, `libresolv`, `libssh`, `libldap`.

**Layer 2** additionally fails on `curl_easy_*`, `curl_multi_*`, `curl_global_*`, `curl_share_*`, and the BSD socket and resolver calls: `socket`, `socketpair`, `connect`, `bind`, `listen`, `accept`, `send*`, `recv*`, `getaddrinfo`, `gethostbyname*`, `getnameinfo`, `inet_*`, `res_*`, `setsockopt`, `getsockopt`, `getpeername`, `getsockname`.

Symbols are anchored (`^_name$`) rather than matched as substrings. Unanchored, `_connect` hits `_dbus_connect` and `_sqlite3_connect`, and `_bind` hits C++ `std::bind` thunks. A false positive here would discredit the scheme faster than a missed bypass, because it accuses an honest author of something.

## Effect on existing badges

None. Checked before landing:

- `steam-shelf`, the only registry entry, still passes.
- Calculator, TextEdit and Chess — ordinary local-only apps — score zero on the new patterns.

## What it does not fix, and the honest shape of this layer

`syscall(97, …)` still passes. Its only import is `_syscall`, which has far too many innocent uses to fail on. That half of [#11](https://github.com/2JIHAN/stays-local/issues/11) stays open.

More importantly: **layer 2 is an enumeration, and an enumeration of ways to reach a network is never finished.** Anything not on the list passes. That was true before this proposal and is true after it; the difference is that the list is now in one reviewable place and `spec/macos.md` says so rather than implying completeness.

## Alternatives considered

Failing on `_syscall` outright. Rejected: too many innocent uses, and a false accusation costs more than a missed bypass.

Treating any undefined symbol from a non-allowlisted dylib as suspicious — an allowlist rather than a blocklist, which would invert the "never finished" problem. Genuinely better in principle, considerably more work, and it needs its own proposal with real false-positive testing behind it. Worth someone taking on.
