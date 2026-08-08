#!/bin/bash
# Runs every executable bypass case against its platform's verifier.
#
#   ./bypasses/run.sh [platform]
#
# Each case declares what is expected of it today, in a file named `expected`:
#
#   caught     the verifier fails this case, and must keep doing so
#   uncaught   the verifier passes this case — a known, documented limit
#
# Only a REGRESSION fails this script: a `caught` case that stops being
# caught. A `uncaught` case that stays uncaught is reported and tolerated,
# because the corpus has to be safe to be honest in. If adding a case that
# nothing catches turned CI red, nobody would add one, and the catalogue
# would quietly become a list of problems we already solved.
#
# A `uncaught` case that starts being caught is progress, and the script says
# so and asks for the file to be updated.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${1:-}"
# Cases are run the way a certification runs. Some bypasses are only caught by
# the runtime layer, and leaving it out would make the verifier look weaker
# than it is. --static skips it when you just want a fast check.
RUNTIME_FLAG="--runtime"
STATIC_ONLY=0
[ "${2:-}" = "--static" ] && { RUNTIME_FLAG=""; STATIC_ONLY=1; }
[ "${1:-}" = "--static" ] && { RUNTIME_FLAG=""; STATIC_ONLY=1; PLATFORM=""; }
REGRESSED=0
UNDECLARED=0
RAN=0
KNOWN_UNCAUGHT=0
IMPROVED=()

for case_dir in "$HERE"/bypasses/*/*/; do
    plat=$(basename "$(dirname "$case_dir")")
    [ -n "$PLATFORM" ] && [ "$plat" != "$PLATFORM" ] && continue
    [ -f "$case_dir/stays-local.json" ] || continue      # documented, not executable
    [ -x "$HERE/verifiers/$plat/verify.sh" ] || continue  # no verifier for it yet

    name=$(basename "$case_dir")
    if [ ! -f "$case_dir/expected" ]; then
        echo "  NO STATUS   $plat/$name — add an 'expected' file containing 'caught' or 'uncaught'"
        UNDECLARED=1
        continue
    fi
    expected=$(tr -d '[:space:]' < "$case_dir/expected")
    RAN=$((RAN + 1))

    # The verifier exits 0 when the app passes — which, for a bypass, means
    # the bypass worked.
    cp "$case_dir/stays-local.json" "$HERE/stays-local.json"
    if ( cd "$HERE" && ./verify.sh . $RUNTIME_FLAG >/dev/null 2>&1 ); then
        actual="uncaught"
    else
        actual="caught"
    fi
    rm -f "$HERE/stays-local.json"

    if [ "$expected" = "caught" ] && [ "$actual" = "uncaught" ]; then
        if [ "$STATIC_ONLY" -eq 1 ]; then
            # Cases caught only by the runtime layer look like regressions here.
            # This mode cannot tell the difference, so it does not get a vote.
            echo "  needs runtime  $plat/$name — not caught without the runtime layer"
        else
            echo "  REGRESSION  $plat/$name — this was caught before and is not any more"
            REGRESSED=1
        fi
    elif [ "$expected" = "uncaught" ] && [ "$actual" = "caught" ]; then
        echo "  IMPROVED    $plat/$name — now caught; update its 'expected' file to 'caught'"
        IMPROVED+=("$plat/$name")
    elif [ "$actual" = "caught" ]; then
        echo "  caught      $plat/$name"
    else
        echo "  uncaught    $plat/$name — known limit, see its case.md"
        KNOWN_UNCAUGHT=$((KNOWN_UNCAUGHT + 1))
    fi
done

echo
if [ "$RAN" -eq 0 ]; then
    # A corpus that runs nothing must not report success. CI would go green on a
    # deleted directory, a broken glob, or a platform filter that matches
    # nothing -- and green would mean "no bypass got through" to anyone reading.
    echo "no executable cases ran — nothing was actually checked"
    [ -n "$PLATFORM" ] && echo "  (no cases for platform \"$PLATFORM\", or no verifier for it)"
    exit 1
fi

echo "$RAN case(s): $((RAN - KNOWN_UNCAUGHT - ${#IMPROVED[@]})) caught, $KNOWN_UNCAUGHT known-uncaught, ${#IMPROVED[@]} newly caught"
if [ "$STATIC_ONLY" -eq 1 ]; then
    echo
    echo "Static mode only — the runtime layer did not run, so this cannot"
    echo "judge a regression. Run without --static before trusting a green."
fi

if [ "$REGRESSED" -ne 0 ]; then
    echo
    echo "A case the verifier used to catch got through. That is a regression in"
    echo "the verifier, not in the corpus — every badge issued since is suspect."
    exit 1
fi
if [ "$UNDECLARED" -ne 0 ]; then
    echo
    echo "A case does not say what is expected of it, so nobody can tell a"
    echo "regression from a known limit. Add its 'expected' file."
    exit 1
fi
exit 0
