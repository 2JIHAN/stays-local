#!/usr/bin/env python3
"""Writes the registry entry and the badge for a verdict.

Every platform verifier calls this instead of carrying its own copy, so a
badge means the same thing and looks the same whatever produced it.

    emit.py <json_out|-> <badge_out|-> <name> <platform> <spec> <failed> [note ...]

`failed` is "0" for a pass and anything else for a fail. Pass "-" for an
output you do not want written.
"""
import json
import sys

# The mark: a cloud outline with a slash cut through it. Fill-only and
# transform-free, so it survives being embedded anywhere; fill-rule=evenodd
# is what makes the slash read as a cut rather than a bar laid on top.
MARK = ('M7 18.4h10.4a4.3 4.3 0 0 0 .5-8.5 6.2 6.2 0 0 0-11.6-2.5A4.7 4.7 0 0 0 7 18.4Z '
        'M7.6 16.3h9.5a2.4 2.4 0 0 0 .3-4.8 4.3 4.3 0 0 0-8-1.7A2.8 2.8 0 0 0 7.6 16.3Z '
        'M2.7 20.2 19.6 2.8l1.6 1.6L4.3 21.8Z')

PASS_COLOR = "0e9f6e"
FAIL_COLOR = "e03131"
LABEL_COLOR = "3b4252"


def badge_svg(message: str, color: str) -> str:
    # ~6.6px per character at 11px Verdana, plus padding either side.
    right = int(len(message) * 6.6) + 16
    left = 93
    total = left + right
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{total}" height="20" role="img" aria-label="stays local: {message}">
  <title>stays local: {message}</title>
  <linearGradient id="s" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <clipPath id="r"><rect width="{total}" height="20" rx="3" fill="#fff"/></clipPath>
  <g clip-path="url(#r)">
    <rect width="{left}" height="20" fill="#{LABEL_COLOR}"/>
    <rect x="{left}" width="{right}" height="20" fill="#{color}"/>
    <rect width="{total}" height="20" fill="url(#s)"/>
  </g>
  <svg x="5" y="3" width="14" height="14" viewBox="0 0 24 24">
    <path fill="#fff" fill-rule="evenodd" d="{MARK}"/>
  </svg>
  <g fill="#fff" font-family="Verdana,DejaVu Sans,Geneva,sans-serif" font-size="11">
    <text x="24" y="15" fill="#010101" fill-opacity=".3">stays local</text>
    <text x="24" y="14">stays local</text>
    <text x="{left + 8}" y="15" fill="#010101" fill-opacity=".3">{message}</text>
    <text x="{left + 8}" y="14">{message}</text>
  </g>
</svg>
'''


def main() -> None:
    json_out, badge_out, name, platform, spec, failed, *notes = sys.argv[1:]
    ok = failed == "0"
    message = "verified" if ok else "failed"
    color = PASS_COLOR if ok else FAIL_COLOR

    if json_out and json_out != "-":
        with open(json_out, "w") as f:
            json.dump({
                "schemaVersion": 1,
                "label": "stays local",
                "message": message,
                "color": color,
                "labelColor": LABEL_COLOR,
                "name": name,
                "platform": platform,
                "spec": spec,
                "notes": notes,
            }, f, indent=2, ensure_ascii=False)
            f.write("\n")

    if badge_out and badge_out != "-":
        with open(badge_out, "w") as f:
            f.write(badge_svg(message, color))


if __name__ == "__main__":
    main()
