#!/usr/bin/env python3
"""Validates a stays-local.json against spec/manifest.schema.json.

    check_manifest.py <path-to-stays-local.json>

Prints one problem per line and exits 1 if there are any. Deliberately
dependency-free: applicants should be able to run the check without
installing anything, and a verifier that needs pip install to tell you your
manifest is wrong is a bad first impression.
"""
import json
import pathlib
import re
import sys

SCHEMA = json.loads(
    (pathlib.Path(__file__).resolve().parents[2] / "spec" / "manifest.schema.json").read_text()
)


def problems(manifest: dict) -> list:
    out = []
    props = SCHEMA["properties"]

    for key in SCHEMA["required"]:
        if key not in manifest:
            out.append(f'missing required field "{key}"')

    for key in manifest:
        if key not in props:
            out.append(f'unknown field "{key}"')

    platform = manifest.get("platform")
    if platform is not None and platform not in props["platform"]["enum"]:
        allowed = ", ".join(props["platform"]["enum"])
        out.append(f'"platform": {platform!r} is not one of: {allowed}')

    for key in ("name", "build", "bundle"):
        if key in manifest and not str(manifest[key]).strip():
            out.append(f'"{key}" is empty')

    repo = manifest.get("repository", "")
    if repo and not re.match(r"^https?://", repo):
        out.append('"repository" must be a public http(s) URL')

    urls = manifest.get("declared_urls")
    if urls is not None:
        if not isinstance(urls, list):
            out.append('"declared_urls" must be a list')
        else:
            for i, entry in enumerate(urls):
                where = f"declared_urls[{i}]"
                if not isinstance(entry, dict):
                    out.append(f"{where} must be an object with url and reason")
                    continue
                url = entry.get("url", "")
                if not url:
                    out.append(f'{where} is missing "url"')
                elif not re.match(r"^[a-zA-Z0-9.-]+$", url):
                    out.append(f"{where}: use the host only, no scheme or path — got {url!r}")
                reason = entry.get("reason", "")
                if len(str(reason).strip()) < 10:
                    out.append(f"{where}: give a real reason; it is published on the registry entry")
    return out


def main() -> None:
    path = sys.argv[1]
    try:
        manifest = json.loads(pathlib.Path(path).read_text())
    except json.JSONDecodeError as e:
        print(f"{path} is not valid JSON: {e}")
        sys.exit(1)

    found = problems(manifest)
    for p in found:
        print(p)
    sys.exit(1 if found else 0)


if __name__ == "__main__":
    main()
