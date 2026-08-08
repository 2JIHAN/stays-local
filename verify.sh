#!/bin/bash
# stays local — dispatcher
#
#   ./verify.sh <subject-dir> [--runtime] [--json out.json] [--badge out.svg]
#
# Reads <subject-dir>/stays-local.json, and hands off to the verifier for the
# platform it declares. Each platform defines its own layers, because what
# counts as evidence differs: on Android the OS enforces the absence of the
# INTERNET permission, while on macOS the strongest signal is what the binary
# links. See spec/ for the definition of each.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUBJECT="${1:-.}"

MANIFEST="$SUBJECT/stays-local.json"
[ -f "$MANIFEST" ] || { echo "No manifest at $MANIFEST"; exit 1; }

# Tell the applicant what is wrong with their manifest before spending a CI
# build on it. Structural problems are cheap to find and annoying to debug
# from a verifier failure three minutes later.
if ! python3 "$HERE/verifiers/_shared/check_manifest.py" "$MANIFEST"; then
    echo
    echo "See spec/core.md and spec/manifest.schema.json"
    exit 1
fi

PLATFORM=$(python3 -c "import json; print(json.load(open('$MANIFEST')).get('platform',''))")

VERIFIER="$HERE/verifiers/$PLATFORM/verify.sh"
if [ ! -x "$VERIFIER" ]; then
    echo "No verifier for platform \"$PLATFORM\"."
    echo
    echo "Implemented:"
    for d in "$HERE"/verifiers/*/; do
        [ -x "$d/verify.sh" ] && echo "  $(basename "$d")"
    done
    echo
    echo "Wanted:"
    for d in "$HERE"/verifiers/*/; do
        [ -x "$d/verify.sh" ] || echo "  $(basename "$d") — see verifiers/$(basename "$d")/README.md and spec/$(basename "$d").md"
    done
    exit 1
fi

exec "$VERIFIER" "$@"
