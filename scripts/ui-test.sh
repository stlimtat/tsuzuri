#!/usr/bin/env bash
# Builds the iOS app and runs its UI flow tests (XCUITest, scheme TsuzuriUITests) in the iOS Simulator, unsigned.
# Usage: scripts/ui-test.sh [simulator name or UDID] [extra xcodebuild args]   (default simulator: iPhone 17)
# Needs Xcode with an iOS Simulator runtime and the named simulator, so scripts/test.sh runs it only when asked
# for by name (`scripts/test.sh UI`). Builds for this Mac's architecture (x86_64 on Intel, arm64 on Apple silicon).
set -euo pipefail
cd "$(dirname "$0")/../Apps/iOS"

simulator="${1:-iPhone 17}"
shift || true
if [[ "$simulator" =~ ^[0-9A-Fa-f-]{36}$ ]]; then destination="platform=iOS Simulator,id=$simulator"
else destination="platform=iOS Simulator,name=$simulator"; fi

out="${TMPDIR:-/tmp}/tsuzuri-ui-test"
xcodebuild test -project Tsuzuri.xcodeproj -scheme TsuzuriUITests -configuration Debug \
  -destination "$destination" -derivedDataPath "$out/derived" \
  -resultBundlePath "$out/results-$(date +%Y%m%d-%H%M%S).xcresult" \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO "$@"
