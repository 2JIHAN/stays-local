#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-.}"
APP="$OUT/Case005.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
# Only the app is built into the bundle. The network-capable helper lives
# outside the bundle on purpose (see helper/) — that is the whole bypass.
swiftc -parse-as-library -target arm64-apple-macos14.0 -o "$APP/Contents/MacOS/Case005" Sources/main.swift
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Case005</string>
<key>CFBundleIdentifier</key><string>local.stays.case005</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
