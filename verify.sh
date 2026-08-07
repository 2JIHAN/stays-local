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

PLATFORM=$(python3 -c "import json; print(json.load(open('$MANIFEST')).get('platform',''))")
[ -n "$PLATFORM" ] || { echo "Manifest has no \"platform\" field. See spec/core.md"; exit 1; }

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
        [ -x "$d/verify.sh" ] || echo "  $(basename "$d") — see $(basename "$d")/README.md and spec/$(basename "$d").md"
    done
    exit 1
fi

exec "$VERIFIER" "$@"
