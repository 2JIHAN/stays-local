#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-.}"
APP="$OUT/Case006.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
clang -o "$APP/Contents/MacOS/Case006" Sources/main.c -lcurl
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Case006</string>
<key>CFBundleIdentifier</key><string>local.stays.case006</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
