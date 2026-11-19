#!/usr/bin/env bash
# Fails unless the archived app is the one the release workflow meant to build and is ready for App Store Connect.
# Usage: scripts/verify-archive.sh <path/to/Tsuzuri.xcarchive> <expected commit SHA> [expected build number]
set -euo pipefail

archive="${1:?usage: $0 <xcarchive> <commit SHA> [build number]}"
expected_commit="${2:?usage: $0 <xcarchive> <commit SHA> [build number]}"
expected_build="${3:-}"
app="$archive/Products/Applications/Tsuzuri.app"
plist="$app/Info.plist"
status=0

fail() { echo "::error::$*" >&2; status=1; }
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }

commit="$(value TsuzuriCommit)"
[[ "$commit" == "$expected_commit" ]] || fail "$plist TsuzuriCommit is '$commit', expected '$expected_commit'"

if [[ -n "$expected_build" ]]; then
  build="$(value CFBundleVersion)"
  [[ "$build" == "$expected_build" ]] || fail "Info.plist CFBundleVersion is '$build', expected '$expected_build'"
fi

[[ "$(value ITSAppUsesNonExemptEncryption)" == false ]] || fail "Info.plist ITSAppUsesNonExemptEncryption is not NO"
[[ -n "$(value CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName)" ]] || fail "Info.plist names no app icon"
[[ -f "$app/PrivacyInfo.xcprivacy" ]] || fail "The app has no PrivacyInfo.xcprivacy"

[[ $status -eq 0 ]] && echo "Archive verified: commit $commit${expected_build:+, build $expected_build}."
exit $status
