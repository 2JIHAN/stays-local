#!/usr/bin/env python3
"""Checks that every registry entry is consistent with its own evidence.

    tools/check-registry.py

The scheme's claim is that a run decides, not that a maintainer asserts. Before
this existed, that was a social convention: the badge is a committed text file
and anyone with write access — the steward most of all — could edit an entry,
rewrite its SVG to match, and every check in the repository would stay green.

This cannot *prevent* a maintainer with write access from forging an entry.
Nothing in a repository can. What it does is make forgery visible: an entry now
has to agree with the badge beside it, with the date it claims, and with a run
in this repository that actually produced it. A hand-edited entry fails here.

Exits 1 on the first inconsistency, listing all of them.
"""
import datetime
import importlib.util
import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = "2JIHAN/stays-local"

spec = importlib.util.spec_from_file_location("emit", ROOT / "verifiers/_shared/emit.py")
emit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(emit)


def problems() -> list:
    out = []
    for f in sorted((ROOT / "registry").glob("*.json")):
        if f.name == "ownership.json":
            continue
        slug = f.stem
        try:
            d = json.loads(f.read_text())
        except json.JSONDecodeError as e:
            out.append(f"{slug}: entry is not valid JSON — {e}")
            continue

        for key in ("message", "platform", "spec", "verified_on", "run", "repository"):
            if key not in d:
                out.append(f"{slug}: entry has no \"{key}\"")
        if out and any(slug in p for p in out):
            continue

        # 1. The badge must be exactly what this entry would generate. A hand
        #    edit to either one shows up as a mismatch.
        badge = ROOT / "badges" / f"{slug}.svg"
        if not badge.exists():
            out.append(f"{slug}: no badge at badges/{slug}.svg")
        else:
            colour = emit.PASS_COLOR if d["message"].startswith("verified") else emit.FAIL_COLOR
            if badge.read_text() != emit.badge_svg(d["message"], colour):
                out.append(
                    f"{slug}: badge does not match the entry — regenerate it from the "
                    f"verdict rather than editing it"
                )

        # 2. The message has to carry the date the entry claims.
        if not d["message"].endswith(d["verified_on"]):
            out.append(
                f"{slug}: message {d['message']!r} does not end with verified_on "
                f"{d['verified_on']!r}"
            )

        # 3. The run has to be a run of this repository.
        m = re.fullmatch(rf"https://github\.com/{re.escape(REPO)}/actions/runs/(\d+)", d["run"])
        if not m:
            out.append(f"{slug}: run {d['run']!r} is not a run of {REPO}")
            continue

        # 4. That run has to exist, have succeeded, and have happened on the day
        #    the entry claims. Skipped without a token so the check still runs
        #    for a contributor offline; CI always has one.
        if not (os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")):
            continue
        try:
            raw = subprocess.run(
                ["gh", "api", f"repos/{REPO}/actions/runs/{m.group(1)}",
                 "--jq", "{conclusion,created_at,name}"],
                capture_output=True, text=True, timeout=30, check=True).stdout
            run = json.loads(raw)
        except Exception as e:
            out.append(f"{slug}: cannot read run {m.group(1)} — {e}")
            continue

        if run.get("conclusion") != "success":
            out.append(f"{slug}: run {m.group(1)} concluded {run.get('conclusion')!r}")
        ran_on = run.get("created_at", "")[:10]
        if ran_on and ran_on != d["verified_on"]:
            out.append(
                f"{slug}: entry says verified_on {d['verified_on']} but run "
                f"{m.group(1)} ran on {ran_on}"
            )
        if run.get("name") not in ("Certify", "Re-verify the registry"):
            out.append(
                f"{slug}: run {m.group(1)} is a {run.get('name')!r} run, which does not "
                f"produce verdicts"
            )
    return out


def main() -> None:
    found = problems()
    for p in found:
        print(p)
    if found:
        print()
        print("An entry that does not agree with its own evidence is the thing this")
        print("scheme exists to catch in other people's software.")
        sys.exit(1)
    print("every registry entry agrees with its badge and its run")


if __name__ == "__main__":
    main()
