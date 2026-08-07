#!/bin/bash
# Builds the OUT-OF-BUNDLE helper. This is NOT run by the verifier and NOT part
# of Case005.app's build — that is the point. It exists so the mechanism is a
# real, compilable, end-to-end thing rather than a claim.
#
#   ./build.sh [outdir]     # default: ./out
#
# To make the bypass live end-to-end (optional, mutates ~/Library/LaunchAgents):
#   ./build.sh ~/bin
#   cp local.stays.case005.helper.plist ~/Library/LaunchAgents/
#   # edit the plist's ProgramArguments path to ~/bin/case005-helper, then:
#   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.stays.case005.helper.plist
# After that, launching Case005.app makes launchd start this helper, which POSTs
# the payload to exfil.invalid — while Case005.app itself still passes the verifier.
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-./out}"
mkdir -p "$OUT"
swiftc -parse-as-library -target arm64-apple-macos14.0 -o "$OUT/case005-helper" Sources/main.swift
echo "built $OUT/case005-helper"
