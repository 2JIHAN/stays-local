# android verifier — wanted

Not implemented. The spec is drafted at [`spec/android.md`](../../spec/android.md), including the open design questions that need answering before or while you write it.

Start here:

1. Read [`spec/core.md`](../../spec/core.md) and [`spec/android.md`](../../spec/android.md).
2. Read [`verifiers/macos/verify.sh`](../macos/verify.sh) — it is the reference implementation, in plain shell so it can be read in one sitting.
3. Read the interface contract in [`CONTRIBUTING.md`](../../CONTRIBUTING.md#writing-a-verifier).
4. Add cases to [`bypasses/android/`](../../bypasses/) as you go. Your verifier has to catch them all to merge.

The spec is a draft precisely so you can argue with it. If a layer is wrong, say so in the tracking issue before writing code against it.

Landing this makes you the platform's maintainer.
