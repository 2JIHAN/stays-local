#!/bin/bash
# stays local — Android verifier, spec v1
#
#   ./verify.sh <subject-dir> [--runtime] [--json out.json] [--badge out.svg]
#
# See spec/android.md. Exits 0 on pass, 1 on fail, and writes a verdict on
# every exit path — a re-verification that cannot build must record a failure,
# or a previous PASS survives untouched and the badge keeps claiming it.
set -uo pipefail

SUBJECT="${1:-.}"; shift 2>/dev/null
RUNTIME=0
JSON_OUT=""
BADGE_OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --runtime) RUNTIME=1 ;;
        --json) shift; JSON_OUT="$1" ;;
        --badge) shift; BADGE_OUT="$1" ;;
    esac
    shift
done

PLATFORM="android"
SPEC="v1"
NAME="unknown"
FAILED=0
NOTES=()
OUT=""
WORK=""
HERE="$(cd "$(dirname "$0")" && pwd)"
EMIT="$HERE/../_shared/emit.py"
DEXREFS="$HERE/dexrefs.py"

fail() { echo "  FAIL  $1"; NOTES+=("FAIL: $1"); FAILED=1; }
pass() { echo "  PASS  $1"; NOTES+=("PASS: $1"); }
note() { echo "  note  $1"; NOTES+=("NOTE: $1"); }
info() { echo "        $1"; }

emit() {
    [ -n "$JSON_OUT$BADGE_OUT" ] || return 0
    python3 "$EMIT" "${JSON_OUT:--}" "${BADGE_OUT:--}" "$NAME" "$PLATFORM" "$SPEC" "$FAILED" \
        ${NOTES[@]+"${NOTES[@]}"}
    [ -n "$JSON_OUT" ] && echo "     wrote $JSON_OUT"
    [ -n "$BADGE_OUT" ] && echo "     wrote $BADGE_OUT"
    return 0
}

die() {
    echo "  FAIL  $1"
    NOTES+=("FAIL: $1")
    FAILED=1
    emit
    [ -n "$OUT" ] && rm -rf "$OUT"
    [ -n "$WORK" ] && rm -rf "$WORK"
    exit 1
}

# The SDK is installed on GitHub runners but never added to PATH, so every
# tool has to be found through ANDROID_HOME. Glob the build-tools version
# rather than pinning: ubuntu-latest carries 34 through 37, macos-15 starts
# at 35, and a pinned version breaks on one of them.
for candidate in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
                 /usr/local/lib/android/sdk "$HOME/Library/Android/sdk" \
                 "$HOME/Android/Sdk"; do
    [ -n "$candidate" ] && [ -d "$candidate/build-tools" ] && { SDK="$candidate"; break; }
done
SDK="${SDK:-/usr/local/lib/android/sdk}"
AAPT2=$(ls -d "$SDK"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)
[ -x "${AAPT2:-}" ] || AAPT2=$(command -v aapt2 2>/dev/null)

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

[ -n "$NAME" ]      || die "manifest has no \"name\""
[ -n "$BUILD_CMD" ] || die "manifest has no \"build\" command"
[ -n "$BUNDLE" ]    || die "manifest has no \"bundle\""
[ -x "${AAPT2:-}" ] || die "aapt2 not found — set ANDROID_HOME (looked in $SDK/build-tools/*/aapt2)"

echo "stays local — $NAME"
echo

# ─────────────────────────────────────────────────────────────
echo "Build"
OUT="$(mktemp -d)"
export STAYS_LOCAL_OUT="$OUT"
( cd "$SUBJECT" && eval "$BUILD_CMD" ) >/dev/null 2>&1 || die "build failed: $BUILD_CMD"
APK="$OUT/$BUNDLE"
[ -f "$APK" ] || die "build produced no APK at $BUNDLE"
info "$BUNDLE  ($(wc -c < "$APK" | tr -d ' ') bytes)"

WORK="$(mktemp -d)"
unzip -q -o "$APK" -d "$WORK" 2>/dev/null || die "cannot unpack the APK"

# ─────────────────────────────────────────────────────────────
echo
echo "1. Permissions (required)"
# Read from the built APK so manifest merging has already happened: a
# dependency can add INTERNET that the app module never declared, and that is
# the case most worth catching. aapt2 rather than `aapt dump badging` or
# apkanalyzer — both of those invent implied permissions that were never
# requested.
PERMS=$("$AAPT2" dump permissions "$APK" 2>&1) \
    || die "aapt2 could not read the APK: $(echo "$PERMS" | tail -1)"

# Match the name on any uses-permission* line. `uses-permission-sdk-23` is a
# real element that requests the same thing, and android:maxSdkVersion appends
# to the line, so the pattern must be anchored at neither end.
NET_PERMS=$(echo "$PERMS" | grep -E "^uses-permission(-sdk-23)?: .*name='(android\.permission\.INTERNET|android\.permission\.ACCESS_NETWORK_STATE)'")
if [ -n "$NET_PERMS" ]; then
    fail "the app requests network permissions"
    echo "$NET_PERMS" | sed 's/^/        /'
else
    pass "no INTERNET or ACCESS_NETWORK_STATE — the OS will refuse it a socket"
fi
OTHER=$(echo "$PERMS" | grep -cE "^uses-permission" || true)
info "$OTHER permission(s) requested in total"

# ─────────────────────────────────────────────────────────────
echo
echo "2. Code references (required)"

FAIL_TYPES='^Ljava/net/(Socket|ServerSocket|DatagramSocket|MulticastSocket|SocketImpl|DatagramSocketImpl|HttpURLConnection|URLConnection|InetAddress|InetSocketAddress|NetworkInterface|ProxySelector);$|^Ljavax/net/(SocketFactory|ssl/SSLSocket|ssl/SSLSocketFactory|ssl/HttpsURLConnection);$|^Ljava/nio/channels/(SocketChannel|ServerSocketChannel|DatagramChannel);$|^Landroid/webkit/(WebView|WebViewClient);$|^Landroid/net/(ConnectivityManager|Network);$|^Lorg/apache/http/'
FAIL_METHODS='^Ljava/net/URL;->(openConnection|openStream|getContent)$'
# Renamed by R8, so their absence proves nothing — a signal, never a verdict.
SOFT_LIBS='^L(okhttp3|okio|retrofit2|com/squareup/okhttp|org/apache/hc|com/android/volley|io/ktor|io/grpc)/'
# The documented dynamic-loading gap in spec/core.md, in its Android form.
DYNAMIC='^Ldalvik/system/DexClassLoader;|^Ljava/lang/reflect/Method;->invoke$|^Ljava/lang/ClassLoader;->loadClass$|^Ljava/lang/Runtime;->exec$|^Ljava/lang/ProcessBuilder;'

REFS=""
DEX_COUNT=0
for dex in "$WORK"/classes*.dex; do
    [ -f "$dex" ] || continue
    DEX_COUNT=$((DEX_COUNT + 1))
    REFS="$REFS$(python3 "$DEXREFS" "$dex" 2>/dev/null)"$'\n'
done
[ "$DEX_COUNT" -gt 0 ] || die "no classes.dex in the APK — nothing to verify"
info "$DEX_COUNT dex file(s)"

HITS=$(echo "$REFS" | grep -E "$FAIL_TYPES" | sort -u)
MHITS=$(echo "$REFS" | grep -E "$FAIL_METHODS" | sort -u)
if [ -n "$HITS$MHITS" ]; then
    fail "networking APIs referenced in the code"
    printf '%s\n%s\n' "$HITS" "$MHITS" | grep -v '^$' | sed 's/^/        /'
else
    pass "no networking classes or URL.openConnection/openStream/getContent"
fi

SOFT=$(echo "$REFS" | grep -oE "$SOFT_LIBS" | sort -u | tr '\n' ' ')
[ -n "$SOFT" ] && note "networking library packages present (R8 may rename these, so this decides nothing): $SOFT"
DYN=$(echo "$REFS" | grep -E "$DYNAMIC" | sort -u | tr '\n' ' ')
[ -n "$DYN" ] && note "dynamic loading present — the known gap in spec/core.md: $DYN"

# Native libraries. Anywhere in the APK, not just lib/: a .so in assets/
# loaded with System.load is a trivial way past a lib/-only scan, and an ELF
# renamed to .dat is the same trick with less typing.
NATIVE_SYMS='^(socket|socketpair|connect|bind|listen|accept|accept4|send|sendto|sendmsg|recv|recvfrom|recvmsg|getaddrinfo|gethostbyname|gethostbyname2|gethostbyaddr|getnameinfo|inet_addr|inet_aton|inet_pton|res_query|res_search|__res_query|setsockopt|getsockopt|getpeername)$'
SO_HITS=""
SO_COUNT=0
while IFS= read -r f; do
    file -b "$f" 2>/dev/null | grep -q "^ELF" || continue
    SO_COUNT=$((SO_COUNT + 1))
    # Strip the @LIBC version tag Bionic puts on every import, and match whole
    # names: `connect` as a substring hits dbus_connect and sqlite3_connect.
    S=$(nm -D --undefined-only "$f" 2>/dev/null \
        | awk '{n=$2; sub(/@.*/,"",n); print n}' | grep -xE "$NATIVE_SYMS" | sort -u)
    [ -n "$S" ] && SO_HITS="$SO_HITS$(basename "$f"): $(echo "$S" | tr '\n' ' ')"$'\n'
done < <(find "$WORK" -type f 2>/dev/null)
if [ -n "$SO_HITS" ]; then
    fail "native libraries import socket calls"
    echo "$SO_HITS" | grep -v '^$' | sed 's/^/        /'
else
    pass "no socket imports in $SO_COUNT native librar$([ "$SO_COUNT" = 1 ] && echo y || echo ies)"
fi

# ─────────────────────────────────────────────────────────────
echo
echo "3. Remote addresses (required)"
# Android keeps strings in four places with three encodings. A verbatim port
# of the macOS layer would find almost none of them: AndroidManifest.xml and
# compiled res/ XML are UTF-16, so plain `strings` returns garbage.
TOOLCHAIN_NOISE='schemas\.android\.com|android\.googlesource\.com|www\.w3\.org|www\.apache\.org|apache\.org|www\.gnu\.org|json-schema\.org|xml\.org|purl\.org|java\.sun\.com|developer\.android\.com|goo\.gl/[A-Za-z]|schemas\.microsoft\.com'

collect_hosts() { grep -aoE "https?://[a-zA-Z0-9._-]+" | sed -E 's|https?://||'; }

FOUND=$(
  {
    for dex in "$WORK"/classes*.dex; do
        [ -f "$dex" ] && python3 "$DEXREFS" "$dex" --strings 2>/dev/null
    done
    "$AAPT2" dump strings "$APK" 2>/dev/null
    "$AAPT2" dump xmlstrings "$APK" --file AndroidManifest.xml 2>/dev/null
    find "$WORK" -type f \( -name '*.so' -o -path '*/assets/*' \) -exec strings -a {} + 2>/dev/null
  } | collect_hosts | grep -avE "^($TOOLCHAIN_NOISE)$" | sort -u
)

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
    if ! command -v adb >/dev/null 2>&1 || ! adb devices 2>/dev/null | grep -q "device$"; then
        info "no emulator attached — skipping this layer"
        NOTES+=("SKIP: runtime layer")
    else
        PKG=$(echo "$PERMS" | awk '/^package:/{print $2; exit}')
        adb install -r "$APK" >/dev/null 2>&1 || info "install failed"
        adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
        sleep 3
        UID_N=$(adb shell "dumpsys package $PKG | grep -m1 userId=" 2>/dev/null | tr -dc '0-9')
        SOCKETS=""
        for _ in $(seq 1 20); do
            H=$(adb shell "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null" 2>/dev/null \
                | awk -v u="$UID_N" 'NR>1 && $8==u')
            [ -n "$H" ] && SOCKETS="$SOCKETS$H"$'\n'
            sleep 1
        done
        adb uninstall "$PKG" >/dev/null 2>&1
        [ -n "$SOCKETS" ] && { fail "sockets were opened"; echo "$SOCKETS" | head -5 | sed 's/^/        /'; } \
                          || pass "no sockets over a 20-second run"
    fi
fi

# ─────────────────────────────────────────────────────────────
echo
[ $FAILED -eq 0 ] && echo "PASS — $NAME meets stays local $PLATFORM $SPEC" \
                  || echo "FAIL — $NAME does not meet stays local $PLATFORM $SPEC"

emit
rm -rf "$OUT" "$WORK"
exit $FAILED
