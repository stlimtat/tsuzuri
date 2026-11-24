#!/usr/bin/env bash
# Runs every Swift package's tests, the iOS app's logic tests (on macOS, no simulator needed), then the scripts' tests.
# Usage: scripts/test.sh [package-name | App | Scripts] [extra test args]
set -euo pipefail
cd "$(dirname "$0")/.."

flags=()
# Command Line Tools (no Xcode) ship swift-testing outside the default search paths.
if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
  dev=/Library/Developer/CommandLineTools/Library/Developer
  flags=(-Xswiftc -F -Xswiftc "$dev/Frameworks" -Xlinker -F -Xlinker "$dev/Frameworks"
         -Xlinker -rpath -Xlinker "$dev/Frameworks" -Xlinker -rpath -Xlinker "$dev/usr/lib")
fi

named="${1:-}"
packages=("$named")
[[ -z "${packages[0]}" ]] && packages=($(ls Packages) App Scripts)
shift || true
for p in "${packages[@]}"; do
  echo "== $p"
  if [[ "$p" == Scripts ]]; then
    bash scripts/verify-archive.test.sh
  elif [[ "$p" == App ]]; then
    if [[ ${#flags[@]} -gt 0 ]]; then
      # Asked for by name, a skip would look like a pass.
      if [[ "$named" == App ]]; then echo "The app's tests need Xcode, not Command Line Tools." >&2; exit 1; fi
      echo "Skipped: the app's tests need Xcode, not Command Line Tools."; continue
    fi
    xcodebuild test -quiet -project Apps/iOS/Tsuzuri.xcodeproj -scheme TsuzuriTests -destination platform=macOS "$@"
  else
    swift test --package-path "Packages/$p" ${flags[@]+"${flags[@]}"} "$@"
  fi
done
