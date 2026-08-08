#!/bin/bash
# Builds the fixture APK with aapt2 + javac + d8 directly — no Gradle, no
# dependencies, no network. About a second and 9 KB.
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-.}"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
BT=$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -1)
PLAT=$(ls -d "$SDK"/platforms/*/android.jar 2>/dev/null | sort -V | tail -1)
[ -n "$BT" ] && [ -n "$PLAT" ] || { echo "no Android SDK under $SDK"; exit 1; }

# CI runners have a JDK on PATH. A developer machine often has only the one
# bundled with Android Studio, and macOS ships a `javac` stub that errors --
# so probe rather than trust. d8, zipalign and apksigner need it too, which is
# why this exports JAVA_HOME instead of only picking a javac.
if ! javac -version >/dev/null 2>&1; then
    for home in "${JAVA_HOME:-}" \
                "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
                /Library/Java/JavaVirtualMachines/*/Contents/Home; do
        [ -x "$home/bin/javac" ] && { export JAVA_HOME="$home"; break; }
    done
    [ -x "${JAVA_HOME:-}/bin/javac" ] || { echo "no JDK found"; exit 1; }
    export PATH="$JAVA_HOME/bin:$PATH"
fi

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

"$BT/aapt2" link -I "$PLAT" --manifest AndroidManifest.xml -o "$W/base.ap_"
javac -nowarn --release 11 -cp "$PLAT" -d "$W/classes" src/*.java
"$BT/d8" --min-api 24 --lib "$PLAT" --output "$W" $(find "$W/classes" -name '*.class')
cp "$W/base.ap_" "$W/app.apk"
( cd "$W" && zip -q app.apk classes.dex )
"$BT/zipalign" -f 4 "$W/app.apk" "$OUT/Case001.apk"
