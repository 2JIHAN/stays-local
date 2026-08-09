# stays local — macOS, spec v1

**Status: stable.** Verifier: `verifiers/macos/verify.sh`.

Read `spec/core.md` first — the claim, the gaps, and the manifest live there.

## Subject

A `.app` bundle built from public source. Every Mach-O inside it is checked, not just the main executable, so a clean main binary with a chatty helper or XPC service does not pass.

"Every Mach-O" means every regular file that `file` identifies as one — not every file with an execute bit. A Mach-O shipped mode 0644 as `.node` or `.jnilib` is loadable code, both are common in real software, and an earlier version of this verifier skipped them.

## Layers

### 1. Linked frameworks — required

No Mach-O in the bundle links `CFNetwork`, `Network.framework`, or `libnetwork`.

Corroborating, not decisive. This layer used to be described as load-bearing, and that was wrong: `Foundation.tbd` exports `NSURLSession` directly and keeps CFNetwork as a delay-init dependency, so a binary can use `URLSession` and carry no CFNetwork load command at all. AltTab, AlDente and Sparkle all do exactly that. Raw BSD `socket`/`connect` come from libSystem, which everything links, so they never appear here either.

A CFNetwork load command is still real evidence and there is no reason to accept one, so the layer stays required — but [layer 2](#2-referenced-symbols--required) is what catches this class. See [`proposals/0001`](../proposals/0001-layer-statuses.md).

### 2. Referenced symbols — required

**The load-bearing layer.** No Mach-O references `URLSession`, `NWConnection`, `CFSocket`, `CFStream`, `NSURLConnection`, `getaddrinfo`, or the raw `connect`/`socket` syscalls, per `nm -u`.

Whatever a binary does or does not link, using the network means naming one of these, and the name survives into the Mach-O where `nm` finds it.

### 3. Remote addresses — required

Every `http://` or `https://` string found by `strings` across the bundle's Mach-O files must appear in `declared_urls` with a reason.

The common legitimate case is a URL handed to the user's browser: the app calls `NSWorkspace.open` or `LSOpenCFURLRef` and never connects itself. Declaring it publishes it on the registry entry — disclosure, not exemption. See the "Known gaps" section of `spec/core.md` for why this layer is weaker than it looks.

### 4. Sockets while running — conditional

The app is launched and watched for 20 seconds with `lsof -nP -i -a -p <pid>`; it must hold zero open sockets. When this layer runs, it decides — an app holding an open socket has failed the claim.

Skipped and noted when the app does not start, which can happen in a headless environment. GitHub's `macos-15` runners do start GUI apps, so certifications run through this layer in practice.

## Running it

```bash
./verify.sh /path/to/repo --runtime
```

Requires macOS with the command line tools (`otool`, `nm`, `strings`, `lsof`).

## Known misses

Layer 2's symbol list is an enumeration, and an enumeration of networking APIs is never finished. Two ordinary, statically linked routes pass every layer today: linking `libcurl` directly, and calling `syscall(97, …)` for a raw socket ([#11](https://github.com/2JIHAN/stays-local/issues/11)). Neither needs dynamic loading. Anyone relying on a macOS badge should read that as the boundary it is.

## Bypasses this spec does not catch

Tracked in `bypasses/macos/`. A verifier change that catches one of these is a welcome contribution; so is a new case.
