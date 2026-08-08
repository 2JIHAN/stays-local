# Proposal: correct two layer statuses on macOS

| | |
|---|---|
| Status | accepted |
| Platforms | macos, core |
| Author | @2JIHAN |
| Opened | 2026-08-08 |

Two criteria-level statements were wrong. Both were found by auditing the repository rather than by anyone reporting a bad badge, and neither invalidates a badge already issued — but both made the spec claim something the code does not do, which is the failure mode this scheme exists to prevent in other people's software.

## 1. Layer 1 does not carry the weight the spec gives it

### What a badge claims today

`spec/macos.md` calls layer 1 **the load-bearing layer** and asserts:

> on macOS, reaching the network cannot be done without linking one of these, and it shows up in `otool -L`

`README.md`, `docs/index.html` and `spec/ios.md` repeat it as the evidence a macOS badge rests on.

### What is wrong with it

It is false. `Foundation.tbd` in the macOS SDK exports `NSURLSession` directly; CFNetwork is a `delay-init` dependency of Foundation that never appears in a client's `otool -L`. A binary can reference `_OBJC_CLASS_$_NSURLSession` and link no CFNetwork at all.

Verified against shipped software rather than argued from documentation — three real applications reference `NSURLSession` with no CFNetwork or `Network.framework` load command:

| Binary | Symbol |
|---|---|
| `AltTab.app/Contents/MacOS/AltTab` | `_OBJC_CLASS_$_NSURLSession` |
| `AlDente.app/Contents/MacOS/AlDente` | `NSURLSession.upload(for:from:delegate:)` |
| `AppCleaner.app/Contents/Frameworks/Sparkle.framework/…/Sparkle` | `_OBJC_CLASS_$_NSURLSession` |

Raw BSD `socket`/`connect` come from libSystem, which every binary links, so they never show in layer 1 either.

Layer 2 is what actually catches this class, and always has.

### Proposed change

Layer 2 becomes the load-bearing layer in the prose. Layer 1 stays **required** — a CFNetwork load command is still real evidence and there is no reason to accept one — but it is described as corroborating rather than decisive.

### Effect on existing badges

None. Layer 2 is required and catches the class layer 1 misses; the one certified entry scores zero on both. This is documentation integrity, not a verifier hole.

`bypasses/macos/001-direct-urlsession/case.md` attributed the catch to "layers 1, 2, and 3". Checked: that build does link CFNetwork, so the attribution happens to be true for this fixture — but it is true by accident of how `swiftc` links it, not by the rule the spec states, and the case now says so.

## 2. Layer 4 is spec'd `recorded` and implemented as deciding

### What a badge claims today

`spec/core.md` defines `recorded` as "published on the registry entry but does not decide the verdict". `spec/macos.md` labels layer 4 `recorded`.

### What is wrong with it

The verifier calls `fail` when it sees a socket, which sets the exit status. So a `recorded` layer decides. Three other platform specs copy the same label for their runtime layers, so three future verifiers would inherit it.

The fix is not to make the code match the spec. An app that holds an open socket while running has failed the only claim this badge makes, and passing it would be absurd. The spec's label was wrong, not the behaviour.

### Proposed change

A third status, `conditional`: **required when the layer can run, skipped and noted when it cannot.** Layer 4 on every platform becomes `conditional`. The registry entry already records `SKIP: runtime layer` when it does not run, so a reader can tell which happened.

### Effect on existing badges

None. The one certified entry passes layer 4 in CI. The change can only turn a false FAIL into a correct one, never a pass into a fail.

## 3. "Every Mach-O in the bundle" was not true either

Discovery selected files with an execute bit **or** a literal `.dylib` name. A Mach-O shipped mode 0644 under another extension — `.node`, `.jnilib`, both common in real software — was skipped by layers 1, 2 and 3 at once. `dlopen` does not require the execute bit, and neither does an ordinary `LC_LOAD_DYLIB`, so this was loadable code that no layer looked at.

Discovery now runs `file` over every regular file in the bundle. This is a bug fix rather than a criteria change: the spec already promised every Mach-O.

## Alternatives considered

Demoting layer 1 to `informational` and dropping it. Rejected: it costs nothing to keep, it catches the honest case, and removing a required layer needs a stronger argument than "one other layer is better".
