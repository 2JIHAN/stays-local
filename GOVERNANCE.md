# Governance

This project issues a badge that other people put on their software. That makes trustworthiness the product, so the rules for changing what the badge means are stricter than the rules for changing code.

## Roles

| Role | Can | Becomes one by |
|---|---|---|
| **Contributor** | Open issues and pull requests | Opening one |
| **Platform maintainer** | Approve code and criteria changes for their platform; certify apps on it | Landing a verifier, or sustained review on an existing one, then nomination by an existing maintainer |
| **Steward** | Approve changes to `spec/core.md`, governance, and the badge itself; break ties | Listed in [MAINTAINERS.md](MAINTAINERS.md) |

Platform maintainers hold authority over their own platform. A change to `spec/android.md` needs Android maintainers; it does not need macOS ones. This is deliberate: platforms differ enough that cross-platform veto power would slow everything down for no gain in quality.

## Decisions

| Change | Requires |
|---|---|
| Code, docs, tooling | 1 maintainer approval |
| A new platform spec (as draft) | 1 steward approval |
| Criteria: adding, removing, or restatusing a layer | Proposal + 2 maintainer approvals + 72 hours open |
| Promoting a spec from draft to stable | Proposal + 2 approvals + a verifier that passes the bypass corpus |
| Certifying an app | 1 platform maintainer triggers the workflow; the CI result decides, not the maintainer |
| Delisting an app | 1 maintainer, immediately, if the check fails. A disputed delisting goes to the stewards |
| Governance and the badge design | 2 steward approvals |

Decisions are made in public issues and pull requests. If a thread stalls, a steward decides and writes down why.

## Certification is not a judgement call

A maintainer starts the run. The run decides. There is no path for a maintainer to certify an app that fails, or to reject one that passes, and no private list of trusted publishers.

If a maintainer believes a passing app should not be certified, the answer is to change the criteria — in public, through the proposal process — not to make an exception. An exception that is not in the spec makes every other badge worth less.

## Conflicts of interest

Maintainers may apply for a badge for their own apps. They may not approve their own certification, and the entry is labelled so anyone can see the relationship. The first entry in the registry is the steward's own app; that is stated on the entry rather than hidden.

## Changing this document

Two steward approvals and seven days open. Governance changes are the one thing that cannot be rushed, because the ability to rush them is what governance exists to prevent.
