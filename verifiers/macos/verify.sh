#!/bin/bash
# stays local — macOS verifier, spec v1
#
# Checks that a macOS app bundle has no way to reach the network.
#
#   ./verify.sh <subject-dir> [--runtime] [--prebuilt dir] [--json out.json] [--badge out.svg]
#
# <subject-dir> must contain a stays-local.json manifest. See spec/macos.md.
# Exits 0 on pass, 1 on fail. A verdict is written on every exit path.
set -uo pipefail

SUBJECT="${1:-.}"; shift 2>/dev/null
RUNTIME=0
PREBUILT=""
JSON_OUT=""
BADGE_OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --runtime) RUNTIME=1 ;;
        --prebuilt) shift; PREBUILT="$1" ;;
        --json) shift; JSON_OUT="$1" ;;
        --badge) shift; BADGE_OUT="$1" ;;
    esac
    shift
done

PLATFORM="macos"
SPEC="v1"
NAME="unknown"
FAILED=0
NOTES=()
OUT=""
EMIT="$(cd "$(dirname "$0")/../_shared" && pwd)/emit.py"

# The applicant's build command is eval'd below, and it runs with the same
# privileges as this script. Nothing stops it from rewriting the code that
# produces the verdict -- so a build that overwrote emit.py could make the
# verifier report PASS on an app it had just failed. Fingerprint everything
# that decides a verdict before the build runs, and refuse to emit if any of
# it changed. This is not a sandbox; it is a tripwire, and it turns a silent
# forgery into a loud failure.
fingerprint() {
    find "$TOOLING" -type f \( -name '*.sh' -o -name '*.py' \) -exec shasum -a 256 {} + \
        2>/dev/null | awk '{print $1}' | sort | shasum -a 256 | awk '{print $1}'
}
TOOLING="$(cd "$(dirname "$0")/.." && pwd)"
TOOLING_BEFORE=$(fingerprint)

# Tools are called by name. A build that drops an `nm` or `otool` earlier on
# PATH would be answering the questions asked about it, so ask the system ones.
PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# What counts as networking, in one place so it can be reviewed as a list
# rather than found inside two greps.
#
# This is an enumeration, and an enumeration of ways to reach a network is
# never finished. Anything not named here passes, which is why spec/macos.md
# says so plainly instead of implying the list is complete.
LINK_PATTERNS="CFNetwork|/Network\.framework|libnetwork|libcurl|libresolv|libssh|libldap"

# Apple frameworks, the C library's socket calls, and the HTTP libraries macOS
# ships. Anchored where a bare word would collide: `_connect` must not match
# `_dbus_connect`, and `_bind` must not match a C++ `std::bind` thunk.
SYMBOL_PATTERNS="urlsession|nwconnection|nsurlconnection|cfsocket|cfstream|cfnetwork"
SYMBOL_PATTERNS="$SYMBOL_PATTERNS|curl_easy_|curl_multi_|curl_global_|curl_share_"
SYMBOL_PATTERNS="$SYMBOL_PATTERNS|^_(socket|socketpair|connect|bind|listen|accept|accept4)\$"
SYMBOL_PATTERNS="$SYMBOL_PATTERNS|^_(send|sendto|sendmsg|recv|recvfrom|recvmsg)\$"
SYMBOL_PATTERNS="$SYMBOL_PATTERNS|^_(getaddrinfo|gethostbyname|gethostbyname2|gethostbyaddr|getnameinfo)\$"
SYMBOL_PATTERNS="$SYMBOL_PATTERNS|^_(inet_addr|inet_aton|inet_pton|inet_ntop)\$"
SYMBOL_PATTERNS="$SYMBOL_PATTERNS|^_(res_query|res_search|res_9_query|res_9_search|__res_query)\$"
SYMBOL_PATTERNS="$SYMBOL_PATTERNS|^_(setsockopt|getsockopt|getpeername|getsockname)\$"

fail() { echo "  FAIL  $1"; NOTES+=("FAIL: $1"); FAILED=1; }
pass() { echo "  PASS  $1"; NOTES+=("PASS: $1"); }
info() { echo "        $1"; }

# Writes the verdict wherever it was asked for. Called on every exit path,
# including the early ones. A re-verification that cannot even build the app
# has to record a failure — otherwise the previous PASS survives untouched and
# the badge goes on claiming something nobody checked.
emit() {
    [ -n "$JSON_OUT$BADGE_OUT" ] || return 0
    # Refuse to speak for a verifier that changed while it was running.
    if [ "$(fingerprint)" != "$TOOLING_BEFORE" ]; then
        echo "  FAIL  the verifier's own code changed during this run — refusing to emit a verdict"
        echo "        (the build command can reach it; see spec/core.md)"
        rm -f "$JSON_OUT" "$BADGE_OUT" 2>/dev/null
        exit 2
    fi
    python3 "$EMIT" "${JSON_OUT:--}" "${BADGE_OUT:--}" "$NAME" "$PLATFORM" "$SPEC" "$FAILED" \
        "${DECLARED_JSON:-[]}" ${NOTES[@]+"${NOTES[@]}"}
    [ -n "$JSON_OUT" ] && echo "     wrote $JSON_OUT"
    [ -n "$BADGE_OUT" ] && echo "     wrote $BADGE_OUT"
    return 0
}

# Fail, say why, record it, stop.
die() {
    echo "  FAIL  $1"
    NOTES+=("FAIL: $1")
    FAILED=1
    emit
    [ -n "$OUT" ] && rm -rf "$OUT"
    exit 1
}

MANIFEST="$SUBJECT/stays-local.json"
[ -f "$MANIFEST" ] || die "no stays-local.json at $MANIFEST"

read_manifest() { python3 -c "
import json
m = json.load(open('$MANIFEST'))
v = m.get('$1', '')
print('\n'.join(x['url'] if isinstance(x, dict) else x for x in v) if isinstance(v, list) else v)
"; }

NAME=$(read_manifest name)
BUILD_CMD=$(read_manifest build)
BUNDLE=$(read_manifest bundle)
DECLARED=$(read_manifest declared_urls)
# The full entries, not just the hosts: the reason is what makes disclosure
# worth anything to someone deciding whether to trust the badge.
DECLARED_JSON=$(python3 -c "
import json
print(json.dumps(json.load(open('$MANIFEST')).get('declared_urls', [])))
")

[ -n "$NAME" ]      || die "manifest has no \"name\""
[ -n "$BUILD_CMD" ] || die "manifest has no \"build\" command"
[ -n "$BUNDLE" ]    || die "manifest has no \"bundle\""

echo "stays local — $NAME"
echo

# ─────────────────────────────────────────────────────────────
echo "Build"
OUT="$(mktemp -d)"
if [ -n "$PREBUILT" ]; then
    # The artifact was produced elsewhere -- in CI, by a job that has none of
    # this code present to tamper with. Nothing the applicant controls has run
    # in this process.
    cp -R "$PREBUILT"/* "$OUT"/ 2>/dev/null || die "cannot read the prebuilt artifact at $PREBUILT"
    info "using a prebuilt artifact"
else
    export STAYS_LOCAL_OUT="$OUT"
    ( cd "$SUBJECT" && eval "$BUILD_CMD" ) >/dev/null 2>&1 \
        || die "build failed: $BUILD_CMD"
fi
APP="$OUT/$BUNDLE"
[ -d "$APP" ] || die "build produced no bundle at $BUNDLE"
info "$BUNDLE"

# Every Mach-O in the bundle, not just the main executable: a clean main binary
# with a chatty helper or XPC service must not pass. Ask `file` about every
# regular file rather than filtering on the execute bit or a .dylib name --
# a Mach-O shipped mode 0644 as .node or .jnilib is loadable code, and both
# are common in real software.
MACHOS=()
while IFS= read -r f; do
    file -b "$f" 2>/dev/null | grep -q "Mach-O" && MACHOS+=("$f")
done < <(find "$APP" -type f 2>/dev/null | sort -u)
[ "${#MACHOS[@]}" -gt 0 ] || die "no Mach-O files in the bundle — nothing to verify"
info "${#MACHOS[@]} Mach-O file(s)"

# ─────────────────────────────────────────────────────────────
echo
echo "1. Linked frameworks (required)"
# Corroborating, not decisive -- see proposals/0001. Foundation exports
# NSURLSession directly and keeps CFNetwork as a delay-init dependency, so a
# binary can use URLSession and link no CFNetwork at all; AltTab, AlDente and
# Sparkle all do. Layer 2 is what catches that class. A CFNetwork load command
# is still real evidence, so this stays required.
HITS=""
for m in "${MACHOS[@]}"; do
    L=$(otool -L "$m" 2>/dev/null | grep -iE "$LINK_PATTERNS")
    [ -n "$L" ] && HITS="$HITS$(basename "$m"): $L"$'\n'
done
[ -n "$HITS" ] && { fail "networking frameworks are linked"; echo "$HITS" | sed 's/^/        /'; } \
               || pass "no CFNetwork or Network.framework"

echo
echo "2. Referenced symbols (required)"
# The load-bearing check. Whatever a binary does or does not link, using the
# network means naming these symbols, and the name survives into the Mach-O.
HITS=""
for m in "${MACHOS[@]}"; do
    S=$(nm -u "$m" 2>/dev/null | grep -iE "$SYMBOL_PATTERNS")
    [ -n "$S" ] && HITS="$HITS$(basename "$m"): $S"$'\n'
done
[ -n "$HITS" ] && { fail "networking symbols are referenced"; echo "$HITS" | sed 's/^/        /'; } \
               || pass "no networking symbols referenced"

echo
echo "3. Remote addresses in the binary (required)"
# Undeclared addresses fail. Declared ones pass but are published on the
# registry entry, so declaring is disclosure rather than an exemption.
FOUND=$(for m in "${MACHOS[@]}"; do strings -a "$m" 2>/dev/null; done \
        | grep -oE "https?://[a-zA-Z0-9._-]+" | sed -E 's|https?://||' | sort -u)
UNDECLARED=""
for host in $FOUND; do
    echo "$DECLARED" | grep -qx "$host" || UNDECLARED="$UNDECLARED $host"
done
if [ -n "$UNDECLARED" ]; then
    fail "undeclared addresses:$UNDECLARED"
else
    pass "every remote address is declared [${FOUND:-none}]"
fi
[ -n "$DECLARED" ] && echo "$DECLARED" | sed 's/^/        declared: /'

# ─────────────────────────────────────────────────────────────
if [ "$RUNTIME" -eq 1 ]; then
    echo
    echo "4. Sockets while running (conditional)"
    EXEC_NAME=$(defaults read "$APP/Contents/Info.plist" CFBundleExecutable 2>/dev/null)
    pkill -x "$EXEC_NAME" 2>/dev/null; sleep 1
    open -a "$APP" 2>/dev/null; sleep 3
    PID=$(pgrep -x "$EXEC_NAME" | head -1)
    if [ -z "$PID" ]; then
        # conditional: required when it can run, skipped and noted when it
        # cannot. An app holding an open socket has failed the only claim this
        # badge makes, so when the layer does run it decides.
        info "app did not start — skipping this layer (headless environment?)"
        NOTES+=("SKIP: runtime layer")
    else
        SOCKETS=""
        for _ in $(seq 1 40); do
            H=$(lsof -nP -i -a -p "$PID" 2>/dev/null | tail -n +2)
            [ -n "$H" ] && SOCKETS="$SOCKETS$H"$'\n'
            sleep 0.5
        done
        pkill -x "$EXEC_NAME" 2>/dev/null
        [ -n "$SOCKETS" ] && { fail "sockets were opened"; echo "$SOCKETS" | sed 's/^/        /'; } \
                          || pass "no sockets over a 20-second run"
    fi
fi

# ─────────────────────────────────────────────────────────────
echo
[ $FAILED -eq 0 ] && echo "PASS — $NAME meets stays local $PLATFORM $SPEC" \
                  || echo "FAIL — $NAME does not meet stays local $PLATFORM $SPEC"

emit
rm -rf "$OUT"
exit $FAILED
