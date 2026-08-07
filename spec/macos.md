# stays local — macOS, spec v1

**Status: stable.** Verifier: `verifiers/macos/verify.sh`.

Read `spec/core.md` first — the claim, the gaps, and the manifest live there.

## Subject

A `.app` bundle built from public source. Every Mach-O inside it is checked, not just the main executable, so a clean main binary with a chatty helper or XPC service does not pass.

## Layers

### 1. Linked frameworks — required

No Mach-O in the bundle links `CFNetwork`, `Network.framework`, or `libnetwork`.

This is the load-bearing layer. Source greps can be worked around; on macOS, reaching the network cannot be done without linking one of these, and it shows up in `otool -L`.

The check is on **direct** load commands. That works on macOS because AppKit and Foundation do not force CFNetwork on a linker that never asks for it — a property that does **not** hold on iOS.

### 2. Referenced symbols — required

No Mach-O references `URLSession`, `NWConnection`, `CFSocket`, `CFStream`, `NSURLConnection`, `getaddrinfo`, or the raw `connect`/`socket` syscalls, per `nm -u`.

### 3. Remote addresses — required

Every `http://` or `https://` string found by `strings` across the bundle's Mach-O files must appear in `declared_urls` with a reason.

The common legitimate case is a URL handed to the user's browser: the app calls `NSWorkspace.open` or `LSOpenCFURLRef` and never connects itself. Declaring it publishes it on the registry entry — disclosure, not exemption. See the "Known gaps" section of `spec/core.md` for why this layer is weaker than it looks.

### 4. Sockets while running — recorded

The app is launched and watched for 20 seconds with `lsof -nP -i -a -p <pid>`; it must hold zero open sockets.

Skipped when the app does not start, which can happen in a headless environment. GitHub's `macos-15` runners do start GUI apps, so certifications run through this layer in practice.

## Running it

```bash
./verify.sh /path/to/repo --runtime
```

Requires macOS with the command line tools (`otool`, `nm`, `strings`, `lsof`).

## Bypasses this spec does not catch

Tracked in `bypasses/macos/`. A verifier change that catches one of these is a welcome contribution; so is a new case.
