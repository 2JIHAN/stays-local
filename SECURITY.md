# Security

The vulnerability that matters here is not a crash. It is **a way for an app that reaches the network to earn this badge**. Every badge in the registry rests on the verifiers being hard to fool, so a bypass is the highest-severity thing you can find.

## What counts

| Report | Severity |
|---|---|
| A technique that gets a passing verdict for an app that exfiltrates data | Critical |
| A technique that passes the required layers but is caught by a recorded layer | High |
| A false verdict caused by the verifier misreading an artifact | High |
| A certified app that actually reaches the network | Critical — treat as a bypass, not a bad entry |
| Injection via a manifest's `build` command into the CI runner | Critical |
| A gap already written down in [`spec/core.md`](spec/core.md) | Not a vulnerability — it is a known gap, and help closing it is welcome in public |

## Reporting

Use [private vulnerability reporting](https://github.com/2JIHAN/stays-local/security/advisories/new). Do not open a public issue for a working bypass until it is fixed, because every currently certified app is affected until then.

Include the mechanism and, if you can, a minimal app that demonstrates it. A repository we can build is worth far more than a description.

We will acknowledge within a week. There is no bounty; this is a volunteer project and saying so up front is more honest than implying otherwise.

## What happens next

1. We confirm the bypass and work out which certified apps could be affected.
2. The verifier is fixed and the case is added to [`bypasses/`](bypasses/) as a permanent regression test, so no future verifier can lose the ability to catch it.
3. Every affected registry entry is re-verified. Entries that now fail have their badges regenerated as `failed`.
4. The advisory is published with credit to the reporter, unless they prefer otherwise.

The bypass corpus is public even though it is a catalogue of attacks. A scheme that hides how it can be fooled is asking to be trusted rather than earning it, and the attacks are not hard to rediscover. Publishing them means every verifier, including ones we did not write, can be tested against the same set.

## The CI runner

Certification builds arbitrary code from applicant repositories on GitHub-hosted runners. That is inherent to the design — a check that trusts the applicant's own build output is not a check. The runner is ephemeral, has no secrets beyond a scoped `GITHUB_TOKEN`, and can only write to `registry/` and `badges/`. Reports about that boundary are in scope.
