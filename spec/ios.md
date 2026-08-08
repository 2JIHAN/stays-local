# stays local — iOS, spec v1 (draft)

**Status: draft. No verifier yet — [help wanted](https://github.com/2JIHAN/stays-local/labels/verifier).**

Read `spec/core.md` first.

iOS looks like macOS and is not, but not for the reason this spec first gave. macOS does not lean on linkage either — [`proposals/0001`](../proposals/0001-layer-statuses.md) established that `Foundation` exports `NSURLSession` directly, so a clean `otool -L` proves little there either, and the symbol scan is what carries the verdict. On iOS that is even more true: `UIKit` drags CFNetwork in on essentially every app, so layer 1 is close to noise rather than merely weaker. Whoever implements this inherits a platform where symbol references are the whole case, and has to decide whether that is enough for the same badge.

## Subject

An `.app` built for the simulator from public source. App Store binaries are FairPlay-encrypted and cannot be scanned, which is consistent with the scheme's rule that only public source can be certified.

## Layers

### 1. Direct linkage — required

The app's own Mach-O declares no direct load command for `CFNetwork` or `Network.framework`.

Weaker than the macOS equivalent, and it must be stated as weaker: transitive linkage through UIKit is expected and ignored. This layer only shows the app did not ask for networking itself.

### 2. Referenced symbols — required

Carries the weight on this platform, in place of linkage. The app's Mach-O must not reference `URLSession`, `NWConnection`, `CFSocket`, `CFStream`, `NSURLConnection`, `getaddrinfo`, `connect`, or `socket`.

Swift name mangling makes this fiddlier than on macOS — `nm -u` output has to be demangled before matching, or the patterns have to cover mangled forms.

### 3. Remote addresses — required

Same rule as every platform. `UIApplication.open` handing a URL to Safari is the legitimate case.

### 4. Sockets while running — conditional

Boot a simulator, install, launch, and observe. `lsof` against the simulator's app process works; a network link conditioner or a proxy that fails closed is a stronger variant worth considering.

## Open questions for whoever implements this

- **Is layer 2 enough?** Without a linkage check that means anything, an iOS badge rests on symbol references alone. If that is too weak, the honest answer may be that iOS gets a lower assurance level rather than the same badge.
- **App extensions.** Widgets and share extensions are separate binaries in the bundle and must be checked, like macOS helpers.
- **Third-party SDKs as static libraries.** They merge into the app binary, so symbol scanning sees them — confirm this holds for XCFrameworks too.
- **`NSAppTransportSecurity`.** Its absence is a hint, never proof. Do not let it into a required layer.
- **Signing in CI.** Simulator builds need no signing, which is why this spec targets them. Confirm that a simulator build's symbol table matches a device build's closely enough for the verdict to transfer.
