# Contributing

Two kinds of change move this project, and they have different bars.

| Kind | Examples | Bar |
|---|---|---|
| **Code** | A verifier, a bug fix, tooling, docs | One maintainer approval |
| **Criteria** | Adding or removing a layer, changing a layer's status, a new platform spec | A proposal, two maintainer approvals, 72 hours open |

Criteria changes are held higher because they change what every existing badge means, retroactively. A code fix affects the next run; a criteria change can make a certified app uncertified.

## Where the work is

**Platform verifiers are the main thing this project needs.** macOS is implemented. Android, Windows, and iOS have specs written and no code.

| Platform | Spec | Verifier |
|---|---|---|
| macOS | [stable](spec/macos.md) | [implemented](verifiers/macos/verify.sh) |
| Android | [stable](spec/android.md) | [implemented](verifiers/android/verify.sh) |
| Windows | [draft](spec/windows.md) | wanted |
| iOS | [draft](spec/ios.md) | wanted |

Windows is the closer of the two — the evidence is the PE import table, much like macOS. iOS needs design work first: `UIKit` drags `CFNetwork` into every app, so the linkage layer that carries macOS proves nothing there, and whoever takes it has to decide what replaces it.

**Bypasses are the second thing.** A badge is only as good as the attacks it survives. [`bypasses/`](bypasses/) is a corpus of apps that reach the network while passing some or all layers. Adding a case that current verifiers miss is a real contribution — arguably a better one than adding a feature. See [`bypasses/README.md`](bypasses/README.md).

Issues labelled `verifier`, `known-gap`, and `good first issue` are the on-ramps.

## Writing a verifier

A verifier is a single executable at `verifiers/<platform>/verify.sh`. The dispatcher hands it the same arguments it received.

```
verify.sh <subject-dir> [--runtime] [--json out.json] [--badge out.svg]
```

| Requirement | Detail |
|---|---|
| Read the manifest | `<subject-dir>/stays-local.json`, per [`spec/core.md`](spec/core.md) |
| Build in a temp dir | Export `STAYS_LOCAL_OUT`, run the manifest's `build`, never write into the subject repo |
| Print each layer | Name, status (`required` / `recorded`), and `PASS` / `FAIL` |
| Exit 0 or 1 | Only `required` layers decide it |
| Emit the same JSON and SVG | Copy the block at the end of the macOS verifier so badges stay identical across platforms |
| Skip, don't fail, when a layer cannot run | A headless runner that cannot launch a GUI records a skip |

Take the macOS verifier as the reference implementation. It is deliberately plain shell so it can be read in one sitting by someone deciding whether to trust it.

Your verifier must catch every case in `bypasses/<platform>/` before it can be merged.

## Proposing a criteria change

1. Open an issue describing the problem, not the solution. What does a badge currently claim that it should not, or fail to claim that it should?
2. If the discussion converges, write a proposal in `proposals/` using [the template](proposals/0000-template.md), as a pull request.
3. The proposal stays open at least 72 hours and needs two maintainer approvals.
4. On merge, the spec and verifier change together. A spec that describes a layer nobody implemented is how a badge starts lying.

Adding a whole platform follows the same path: the spec lands as a draft first, so people can argue about the layers before anyone writes code against them.

## Pull requests

Titles follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(android): verify the merged manifest declares no INTERNET permission
fix(macos): match Swift-mangled URLSession symbols
docs: state that declared URLs can carry data
spec(windows): draft the delay-load layer
```

Every commit needs a [Developer Certificate of Origin](https://developercertificate.org/) sign-off:

```bash
git commit -s -m "..."
```

That is a statement that you wrote the change or have the right to submit it. There is no CLA.

Explain *why* in the body. The what is in the diff.

## Reporting a badge you think is wrong

Open a [dispute](https://github.com/2JIHAN/stays-local/issues/new?template=dispute.yml). You do not need proof — a plausible mechanism is enough to start the conversation.

If the app really does reach the network, that is a verifier bug first and a bad entry second. The app gets delisted and the mechanism gets added to `bypasses/` so no verifier can regress on it.

If you have a working bypass that would let a malicious app carry this badge, please read [SECURITY.md](SECURITY.md) before opening it in public.

## Code of conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
