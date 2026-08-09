#!/bin/bash
# stays local — dispatcher
#
#   ./verify.sh <subject-dir> [--runtime] [--json out.json] [--badge out.svg]
#
# Reads <subject-dir>/stays-local.json, and hands off to the verifier for the
# platform it declares. Each platform defines its own layers, because what
# counts as evidence differs: on Android the OS enforces the absence of the
# INTERNET permission, while on macOS it is inferred from the symbols a binary
# names. See spec/ for the definition of each, and proposals/0001 for why
# linkage is not the macOS signal it was once described as.
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
        p=$(basename "$d")
        [ "$p" = "_shared" ] && continue          # code the verifiers share, not a platform
        [ -x "$d/verify.sh" ] && echo "  $p"
    done
    echo
    echo "Wanted — landing one makes you that platform's maintainer:"
    for d in "$HERE"/verifiers/*/; do
        p=$(basename "$d")
        [ "$p" = "_shared" ] && continue
        [ -x "$d/verify.sh" ] || echo "  $p — see verifiers/$p/README.md and spec/$p.md"
    done
    exit 1
fi

exec "$VERIFIER" "$@"
