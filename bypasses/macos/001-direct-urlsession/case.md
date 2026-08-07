# 001 — direct URLSession

**Mechanism.** The app references `URLSession` and a remote URL directly, with no attempt to hide it.

**Expected verdict.** `FAIL`.

**Caught by.** Layers 1, 2, and 3 — the binary links `CFNetwork`, references `_OBJC_CLASS_$_NSURLSession`, and carries an undeclared address.

This is the floor. A verifier that misses this is broken, which is what makes it useful as a smoke test: it is the case that proves the checks are wired up at all.
