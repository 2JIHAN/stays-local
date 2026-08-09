# stays local — core spec

Platform-independent rules. Each platform adds its own layers on top; see `spec/<platform>.md`.

## The claim

**The app's shipped code contains no way to reach the network.**

That is the whole claim. It is narrow on purpose, because it is the part that can actually be checked.

## What the badge does not claim

Read this before trusting a badge.

| Not covered | Why |
|---|---|
| Code the app shells out to | `curl` in a script the app runs is invisible to a binary scan |
| IPC to another process | The app can ask a service that does have network access |
| Files written for another app to upload | Nothing leaves *this* process; something else may carry it |
| Code loaded at runtime | A plugin or downloaded library is not in the artifact we checked |
| Data smuggled in a declared URL | See "Known gaps" below — this one is unsolved |
| The binary you downloaded | We check a build from public source. Build provenance is a separate problem |

It is one checkable property, not a privacy audit. Say so when you cite it.

## Known gaps

These are open, and we would rather write them down than let a badge imply more than it earns. Each has an issue labelled `known-gap`.

**Declared URLs can carry data.** Layer "declared addresses" lets an app hand a URL to the user's browser. Nothing currently stops that URL from being built with data in the query string. Static analysis of whether a URL is a constant is possible but not implemented, and a determined app can defeat it. Today this is mitigated only by disclosure: every declared address is published on the registry entry, with the reason, where anyone can object.

**Dynamic loading defeats static linkage checks.** An app that resolves a networking symbol at runtime passes the static layers. The runtime layer catches this only if the app actually connects during the observation window.

**The observation window is short.** An app that waits an hour before its first connection passes.

## Requirements on the subject

| Requirement | Why |
|---|---|
| Public source | A claim you cannot inspect is the thing this scheme exists to replace |
| Builds with no secrets | The check builds it in neutral CI, not on the author's machine |
| Reproducible enough to build twice | Re-verification must be able to reach the same verdict |

## Manifest

`stays-local.json` in the repository root.

```json
{
  "name": "Your App",
  "platform": "macos",
  "repository": "https://github.com/you/your-app",
  "build": "./build.sh \"$STAYS_LOCAL_OUT\"",
  "bundle": "Your App.app",
  "declared_urls": [
    { "url": "example.com", "reason": "Opened in the user's browser; the app never connects" }
  ]
}
```

| Field | Meaning |
|---|---|
| `name` | Display name on the registry |
| `platform` | `macos`, `ios`, `android`, or `windows` |
| `repository` | Public source. Required |
| `build` | Command that builds the artifact into `$STAYS_LOCAL_OUT`. No secrets |
| `bundle` | Artifact name inside `$STAYS_LOCAL_OUT` (`.app`, `.apk`, `.exe`, …) |
| `declared_urls` | Every remote address in the artifact, each with a reason |

Platform specs may require additional fields.

## Layer status

Each layer in a platform spec is one of:

| Status | Meaning |
|---|---|
| **required** | Failing it fails the certification |
| **conditional** | Required when the layer can run; skipped and noted when it cannot |
| **recorded** | Result is published on the registry entry but does not decide the verdict |
| **informational** | Reported to help review; never affects the verdict |

The runtime layers are `conditional`: an app holding an open socket has failed the only claim this badge makes, so when the layer runs it decides — but headless CI cannot always launch a GUI app, and a layer that did not run must not be mistaken for one that passed. The registry entry records `SKIP` when it did not run, so a reader can tell which happened. See [`proposals/0001`](../proposals/0001-layer-statuses.md).

## Certification process

1. Applicant adds `stays-local.json` and opens an application issue.
2. A maintainer triggers the certify workflow, which checks out the applicant's public source in this repository's CI and runs the verifier there. Applicants do not certify themselves.
3. On pass, the run writes `registry/<slug>.json` and `badges/<slug>.svg`, and the run URL is recorded on the entry.
4. The badge and the entry carry the date they were earned. Re-verification is manual: a maintainer re-runs the check on request or when something looks wrong, and a failing re-verification regenerates the badge as `failed`. It is not scheduled, because building an applicant's current source on a timer executes code nobody chose to run that week.

## Disputes

Anyone can open a dispute issue against a certified app. A dispute that demonstrates network access the badge did not catch is treated as a verifier bug, not just a bad entry: the app is delisted *and* a bypass case is added to `bypasses/` so no verifier can regress on it. See `SECURITY.md`.

## Spec versioning

Platform specs are versioned independently (`macos v1`, `android v1`, …), because a change to Android's layers should not invalidate macOS entries. Registry entries record which spec version certified them.

Changing a layer's status or adding a required layer is a **criteria change** and carries a higher bar than a code change. See `GOVERNANCE.md`.
