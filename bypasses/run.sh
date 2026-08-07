#!/bin/bash
# Runs every executable bypass case against its platform's verifier and checks
# that the verdict matches the case's expectation. A verifier that stops
# catching a case fails here.
#
#   ./bypasses/run.sh [platform]
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${1:-}"
FAILED=0
RAN=0

for case_dir in "$HERE"/bypasses/*/*/; do
    plat=$(basename "$(dirname "$case_dir")")
    [ -n "$PLATFORM" ] && [ "$plat" != "$PLATFORM" ] && continue
    [ -f "$case_dir/stays-local.json" ] || continue      # documented, not executable
    [ -x "$HERE/verifiers/$plat/verify.sh" ] || continue  # no verifier yet

    name=$(basename "$case_dir")
    RAN=$((RAN + 1))
    # Cases are expected to FAIL. Passing means the verifier missed the bypass.
    if ( cd "$HERE" && cp "$case_dir/stays-local.json" ./stays-local.json \
         && ./verify.sh . >/dev/null 2>&1 ); then
        echo "  MISSED  $plat/$name — the verifier passed a known bypass"
        FAILED=1
    else
        echo "  caught  $plat/$name"
    fi
    rm -f "$HERE/stays-local.json"
done

echo
if [ "$RAN" -eq 0 ]; then
    echo "no executable cases ran"
elif [ "$FAILED" -eq 0 ]; then
    echo "all $RAN case(s) caught"
else
    echo "a known bypass got through"
fi
exit $FAILED
