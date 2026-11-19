#!/usr/bin/env bash
# Tests scripts/verify-archive.sh against fixture archives built in a temporary directory.
set -euo pipefail
cd "$(dirname "$0")/.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sha=0123456789abcdef0123456789abcdef01234567
failures=0

# A fixture archive holding a release-ready app; each case then breaks one thing.
fixture() {
  local archive="$work/$1.xcarchive" app
  app="$archive/Products/Applications/Tsuzuri.app"
  mkdir -p "$app"
  plutil -create xml1 "$app/Info.plist"
  plutil -insert TsuzuriCommit -string "$sha" "$app/Info.plist"
  plutil -insert CFBundleVersion -string 42 "$app/Info.plist"
  plutil -insert ITSAppUsesNonExemptEncryption -bool NO "$app/Info.plist"
  plutil -insert CFBundleIcons -json '{"CFBundlePrimaryIcon":{"CFBundleIconName":"AppIcon"}}' "$app/Info.plist"
  touch "$app/PrivacyInfo.xcprivacy"
  echo "$archive"
}

expect() { # expect pass|fail <name> <verify-archive args...>
  local want="$1" name="$2" got=pass
  shift 2
  scripts/verify-archive.sh "$@" >/dev/null 2>&1 || got=fail
  if [[ "$got" == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (wanted $want, got $got)"; failures=$((failures + 1)); fi
}

a="$(fixture good)"
expect pass "release-ready archive with the expected commit and build" "$a" "$sha" 42
expect pass "build number is optional" "$a" "$sha"
expect fail "commit differs from the workflow's" "$a" fedcba9876543210fedcba9876543210fedcba98
expect fail "build number differs from the run number" "$a" "$sha" 43

a="$(fixture no-commit)"; plutil -remove TsuzuriCommit "$a/Products/Applications/Tsuzuri.app/Info.plist"
expect fail "Info.plist lacks the commit" "$a" "$sha"

a="$(fixture empty-commit)"; plutil -replace TsuzuriCommit -string "" "$a/Products/Applications/Tsuzuri.app/Info.plist"
expect fail "Info.plist commit is empty (a local build)" "$a" "$sha"

a="$(fixture encryption)"; plutil -replace ITSAppUsesNonExemptEncryption -bool YES "$a/Products/Applications/Tsuzuri.app/Info.plist"
expect fail "encryption flag is not NO" "$a" "$sha"

a="$(fixture no-icon)"; plutil -remove CFBundleIcons "$a/Products/Applications/Tsuzuri.app/Info.plist"
expect fail "app has no icon" "$a" "$sha"

a="$(fixture no-privacy)"; rm "$a/Products/Applications/Tsuzuri.app/PrivacyInfo.xcprivacy"
expect fail "app has no privacy manifest" "$a" "$sha"

expect fail "archive has no app" "$work/missing.xcarchive" "$sha"

[[ $failures -eq 0 ]] && echo "All verify-archive cases passed." || { echo "$failures verify-archive case(s) failed."; exit 1; }
