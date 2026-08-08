#!/usr/bin/env python3
"""Rewrites the Registry table in README.md from the registry itself.

    tools/render-registry.py [--check]

The table was hand-written, which meant the declared addresses a reader sees
and the ones the check actually accepted could drift apart with nobody
noticing. --check exits 1 if the file is out of date, so CI can say so.
"""
import json
import pathlib
import sys

START = "<!-- registry:start -->"
END = "<!-- registry:end -->"


def rows() -> str:
    ownership = {}
    own_path = pathlib.Path("registry/ownership.json")
    if own_path.exists():
        ownership = json.loads(own_path.read_text())

    out = ["| App | Platform | Badge | Declared addresses | |",
           "|---|---|---|---|---|"]
    for f in sorted(pathlib.Path("registry").glob("*.json")):
        if f.name == "ownership.json":
            continue
        d = json.loads(f.read_text())
        declared = d.get("declared_urls") or []
        if declared:
            cell = "<br>".join(f"`{e['url']}` — {e['reason']}" for e in declared)
        else:
            cell = "*none*"
        mark = "⚠︎ steward's own app" if ownership.get(f.stem, {}).get("maintainer_owned") else ""
        out.append(
            f"| [{d['name']}]({d['repository']}) | {d.get('platform', '?')} "
            f"| ![]({'badges/' + f.stem + '.svg'}) | {cell} | {mark} |"
        )
    return "\n".join(out)


def main() -> None:
    p = pathlib.Path("README.md")
    text = p.read_text()
    a, b = text.index(START) + len(START), text.index(END)
    updated = text[:a] + "\n" + rows() + "\n" + text[b:]
    if "--check" in sys.argv:
        if updated != text:
            print("README's registry table is out of date — run tools/render-registry.py")
            sys.exit(1)
        print("registry table is current")
        return
    p.write_text(updated)
    print("README registry table rewritten")


if __name__ == "__main__":
    main()
