# 001 — direct URLSession

**Mechanism.** The app references `URLSession` and a remote URL directly, with no attempt to hide it.

**Expected verdict.** `FAIL`.

**Caught by.** Layers 2 and 3 — the binary references `_OBJC_CLASS_$_NSURLSession` and carries an undeclared address.

Layer 1 also fires here, because this particular `swiftc` build happens to emit a `CFNetwork` load command. Do not read that as the rule: `Foundation` exports `NSURLSession` directly, and real apps use it with no CFNetwork linkage at all — AltTab, AlDente and Sparkle among them. Layer 2 is what makes this case fail. See [`proposals/0001`](../../../proposals/0001-layer-statuses.md).

This is the floor. A verifier that misses this is broken, which is what makes it useful as a smoke test: it is the case that proves the checks are wired up at all.
