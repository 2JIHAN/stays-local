#!/bin/bash
# stays local — 검증기 v1
#
# macOS 앱 번들이 밖으로 나가는 연결을 열지 않는지 검사한다.
#
#   ./verify.sh <subject-dir> [--runtime] [--json out.json]
#
# <subject-dir>에 stays-local.json 매니페스트가 있어야 한다. 자세한 형식은 SPEC.md 참고.
# 통과하면 0, 실패하면 1로 끝난다.
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
[ -f "$MANIFEST" ] || { echo "stays-local.json 이 없습니다: $MANIFEST"; exit 1; }

read_manifest() { python3 -c "
import json,sys
m = json.load(open('$MANIFEST'))
print(m.get('$1', '') if not isinstance(m.get('$1'), list) else '\n'.join(
    x['url'] if isinstance(x, dict) else x for x in m.get('$1', [])))
"; }

NAME=$(read_manifest name)
BUILD_CMD=$(read_manifest build)
BUNDLE=$(read_manifest bundle)
DECLARED=$(read_manifest declared_urls)

FAILED=0
NOTES=()
fail() { echo "  ❌ $1"; NOTES+=("FAIL: $1"); FAILED=1; }
pass() { echo "  ✅ $1"; NOTES+=("PASS: $1"); }
info() { echo "  ·  $1"; }

echo "stays local — $NAME"
echo

# ─────────────────────────────────────────────────────────────
echo "▸ 빌드"
OUT="$(mktemp -d)"
export STAYS_LOCAL_OUT="$OUT"
( cd "$SUBJECT" && eval "$BUILD_CMD" ) >/dev/null 2>&1 || { echo "  빌드 실패: $BUILD_CMD"; exit 1; }
APP="$OUT/$BUNDLE"
[ -d "$APP" ] || { echo "  번들을 찾을 수 없습니다: $APP"; exit 1; }
info "$BUNDLE"

# 번들 안의 모든 Mach-O 실행 파일. 헬퍼·XPC·내장 프레임워크까지 포함해야
# "메인 바이너리만 깨끗한" 경우를 걸러낼 수 있다.
MACHOS=()
while IFS= read -r f; do
    file -b "$f" 2>/dev/null | grep -q "Mach-O" && MACHOS+=("$f")
done < <(find "$APP" -type f -perm +111 -o -type f -name "*.dylib" -o -type f -name "*.framework" 2>/dev/null | sort -u)
info "Mach-O ${#MACHOS[@]}개 검사"

# ─────────────────────────────────────────────────────────────
echo
echo "▸ 1. 링크된 프레임워크 (필수)"
# 원격 접속을 하는 코드는 어떤 경로로 짜든 결국 CFNetwork를 끌고 온다.
# 소스 grep은 우회할 수 있지만 이건 바이너리에 남는다.
HITS=""
for m in "${MACHOS[@]}"; do
    L=$(otool -L "$m" 2>/dev/null | grep -iE "CFNetwork|/Network\.framework|libnetwork")
    [ -n "$L" ] && HITS="$HITS$(basename "$m"): $L"$'\n'
done
[ -n "$HITS" ] && { fail "네트워킹 프레임워크 링크됨"; echo "$HITS" | sed 's/^/     /'; } \
               || pass "CFNetwork·Network.framework 링크 없음"

echo
echo "▸ 2. 참조 심볼 (필수)"
HITS=""
for m in "${MACHOS[@]}"; do
    S=$(nm -u "$m" 2>/dev/null | grep -iE "urlsession|nwconnection|cfsocket|cfstream|getaddrinfo|nsurlconnection|_connect\$|_socket\$")
    [ -n "$S" ] && HITS="$HITS$(basename "$m"): $S"$'\n'
done
[ -n "$HITS" ] && { fail "네트워킹 심볼 참조"; echo "$HITS" | sed 's/^/     /'; } \
               || pass "네트워킹 심볼 참조 없음"

echo
echo "▸ 3. 바이너리에 박힌 원격 주소 (필수)"
# 신고하지 않은 주소가 나오면 실패. 신고한 주소는 통과하되 등록부에 공개된다.
FOUND=$(for m in "${MACHOS[@]}"; do strings -a "$m" 2>/dev/null; done \
        | grep -oE "https?://[a-zA-Z0-9._-]+" | sed -E 's|https?://||' | sort -u)
UNDECLARED=""
for host in $FOUND; do
    echo "$DECLARED" | grep -qx "$host" || UNDECLARED="$UNDECLARED $host"
done
if [ -n "$UNDECLARED" ]; then
    fail "신고되지 않은 주소:$UNDECLARED"
else
    pass "원격 주소는 신고된 것뿐 [${FOUND:-없음}]"
fi
[ -n "$DECLARED" ] && echo "$DECLARED" | sed 's/^/     신고됨: /'

# ─────────────────────────────────────────────────────────────
if [ "$RUNTIME" -eq 1 ]; then
    echo
    echo "▸ 4. 실행 중 소켓 (선택)"
    EXEC_NAME=$(defaults read "$APP/Contents/Info.plist" CFBundleExecutable 2>/dev/null)
    pkill -x "$EXEC_NAME" 2>/dev/null; sleep 1
    open -a "$APP" 2>/dev/null; sleep 3
    PID=$(pgrep -x "$EXEC_NAME" | head -1)
    if [ -z "$PID" ]; then
        info "앱이 실행되지 않아 이 층은 건너뜁니다 (헤드리스 환경일 수 있음)"
        NOTES+=("SKIP: runtime")
    else
        SOCKETS=""
        for _ in $(seq 1 40); do
            H=$(lsof -nP -i -a -p "$PID" 2>/dev/null | tail -n +2)
            [ -n "$H" ] && SOCKETS="$SOCKETS$H"$'\n'
            sleep 0.5
        done
        pkill -x "$EXEC_NAME" 2>/dev/null
        [ -n "$SOCKETS" ] && { fail "소켓이 열렸습니다"; echo "$SOCKETS" | sed 's/^/     /'; } \
                          || pass "20초 동안 열린 소켓 0개"
    fi
fi

# ─────────────────────────────────────────────────────────────
echo
if [ $FAILED -eq 0 ]; then
    echo "✅ 통과 — $NAME 은 stays local 기준을 만족합니다"
else
    echo "❌ 실패 — $NAME 은 기준을 만족하지 않습니다"
fi

if [ -n "$JSON_OUT" ]; then
    python3 - "$JSON_OUT" "$NAME" "$FAILED" "${NOTES[@]}" <<'PY'
import json, sys
out, name, failed, *notes = sys.argv[1:]
# 배지에 제도의 마크(사선 그은 구름)를 함께 싣는다.
LOGO = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14">'
        '<g fill="none" stroke="#fff" stroke-width="1.3" stroke-linecap="round" '
        'stroke-linejoin="round">'
        '<path d="M3.6 10.2h5.6a2.3 2.3 0 0 0 .2-4.6 3.3 3.3 0 0 0-6-1.2 2.6 2.6 0 0 0-.6 5.1z"/>'
        '<path d="M1.5 12.4 11.1 2.8"/></g></svg>')

json.dump({
    "schemaVersion": 1,
    "label": "stays local",
    "message": "verified" if failed == "0" else "failed",
    "color": "0e9f6e" if failed == "0" else "e03131",
    "labelColor": "3b4252",
    "logoSvg": LOGO,
    "name": name,
    "spec": "v1",
    "notes": notes,
}, open(out, "w"), indent=2, ensure_ascii=False)
PY
    echo "   → $JSON_OUT"
fi

rm -rf "$OUT"
exit $FAILED
