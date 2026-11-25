#!/usr/bin/env bash
# Builds the iOS app for the iOS Simulator, unsigned. Usage: scripts/build-app.sh [extra xcodebuild args]
# A target build (not a scheme build) so it works without a simulator runtime installed.
set -euo pipefail
cd "$(dirname "$0")/../Apps/iOS"

out="${TMPDIR:-/tmp}/tsuzuri-build-app"
xcodebuild build -project Tsuzuri.xcodeproj -target Tsuzuri -configuration Debug -sdk iphonesimulator \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO SYMROOT="$out/sym" OBJROOT="$out/obj" "$@"
