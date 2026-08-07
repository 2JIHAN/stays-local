#!/bin/bash
# stays local — verifier, spec v1
#
# Checks that a macOS app bundle has no way to reach the network.
#
#   ./verify.sh <subject-dir> [--runtime] [--json out.json]
#
# <subject-dir> must contain a stays-local.json manifest. See SPEC.md.
# Exits 0 on pass, 1 on fail.
set -uo pipefail

SUBJECT="${1:-.}"; shift 2>/dev/null
RUNTIME=0
JSON_OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --runtime) RUNTIME=1 ;;
        --json) shift; JSON_OUT="$1" ;;
    esac
    shift
done

MANIFEST="$SUBJECT/stays-local.json"
[ -f "$MANIFEST" ] || { echo "No manifest at $MANIFEST"; exit 1; }

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

FAILED=0
NOTES=()
fail() { echo "  FAIL  $1"; NOTES+=("FAIL: $1"); FAILED=1; }
pass() { echo "  PASS  $1"; NOTES+=("PASS: $1"); }
info() { echo "        $1"; }

echo "stays local — $NAME"
echo

# ─────────────────────────────────────────────────────────────
echo "Build"
OUT="$(mktemp -d)"
export STAYS_LOCAL_OUT="$OUT"
( cd "$SUBJECT" && eval "$BUILD_CMD" ) >/dev/null 2>&1 \
    || { echo "  Build failed: $BUILD_CMD"; exit 1; }
APP="$OUT/$BUNDLE"
[ -d "$APP" ] || { echo "  No bundle at $APP"; exit 1; }
info "$BUNDLE"

# Every Mach-O in the bundle, not just the main executable. A clean main
# binary with a chatty helper or XPC service must not pass.
MACHOS=()
while IFS= read -r f; do
    file -b "$f" 2>/dev/null | grep -q "Mach-O" && MACHOS+=("$f")
done < <(find "$APP" -type f \( -perm +111 -o -name "*.dylib" \) 2>/dev/null | sort -u)
info "${#MACHOS[@]} Mach-O file(s)"

# ─────────────────────────────────────────────────────────────
echo
echo "1. Linked frameworks (required)"
# The load-bearing check. Source greps can be worked around, but reaching the
# network cannot be done without linking these, and that shows up in otool -L.
HITS=""
for m in "${MACHOS[@]}"; do
    L=$(otool -L "$m" 2>/dev/null | grep -iE "CFNetwork|/Network\.framework|libnetwork")
    [ -n "$L" ] && HITS="$HITS$(basename "$m"): $L"$'\n'
done
[ -n "$HITS" ] && { fail "networking frameworks are linked"; echo "$HITS" | sed 's/^/        /'; } \
               || pass "no CFNetwork or Network.framework"

echo
echo "2. Referenced symbols (required)"
HITS=""
for m in "${MACHOS[@]}"; do
    S=$(nm -u "$m" 2>/dev/null | grep -iE "urlsession|nwconnection|cfsocket|cfstream|getaddrinfo|nsurlconnection|_connect\$|_socket\$")
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
    echo "4. Sockets while running (recorded)"
    EXEC_NAME=$(defaults read "$APP/Contents/Info.plist" CFBundleExecutable 2>/dev/null)
    pkill -x "$EXEC_NAME" 2>/dev/null; sleep 1
    open -a "$APP" 2>/dev/null; sleep 3
    PID=$(pgrep -x "$EXEC_NAME" | head -1)
    if [ -z "$PID" ]; then
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
[ $FAILED -eq 0 ] && echo "PASS — $NAME meets stays local v1" \
                  || echo "FAIL — $NAME does not meet stays local v1"

if [ -n "$JSON_OUT" ]; then
    python3 - "$JSON_OUT" "$NAME" "$FAILED" "${NOTES[@]}" <<'PY'
import json, sys
out, name, failed, *notes = sys.argv[1:]

# The scheme's mark: a cloud outline with a slash through it. Fill-only and
# transform-free — Shields strips stroke-based logos.
MARK = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path fill="#fff" fill-rule="evenodd" d="'
    'M7 18.4h10.4a4.3 4.3 0 0 0 .5-8.5 6.2 6.2 0 0 0-11.6-2.5A4.7 4.7 0 0 0 7 18.4Z '
    'M7.6 16.3h9.5a2.4 2.4 0 0 0 .3-4.8 4.3 4.3 0 0 0-8-1.7A2.8 2.8 0 0 0 7.6 16.3Z '
    'M2.7 20.2 19.6 2.8l1.6 1.6L4.3 21.8Z"/></svg>'
)

json.dump({
    "schemaVersion": 1,
    "label": "stays local",
    "message": "verified" if failed == "0" else "failed",
    "color": "0e9f6e" if failed == "0" else "e03131",
    "labelColor": "3b4252",
    "logoSvg": MARK,
    "name": name,
    "spec": "v1",
    "notes": notes,
}, open(out, "w"), indent=2, ensure_ascii=False)
PY
    echo "     wrote $JSON_OUT"
fi

rm -rf "$OUT"
exit $FAILED
