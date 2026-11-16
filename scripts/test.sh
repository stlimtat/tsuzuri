#!/usr/bin/env bash
# Runs every Swift package's tests. Usage: scripts/test.sh [package-name] [extra swift test args]
set -euo pipefail
cd "$(dirname "$0")/.."

flags=()
# Command Line Tools (no Xcode) ship swift-testing outside the default search paths.
if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
  dev=/Library/Developer/CommandLineTools/Library/Developer
  flags=(-Xswiftc -F -Xswiftc "$dev/Frameworks" -Xlinker -F -Xlinker "$dev/Frameworks"
         -Xlinker -rpath -Xlinker "$dev/Frameworks" -Xlinker -rpath -Xlinker "$dev/usr/lib")
fi

packages=("${1:-}")
[[ -z "${packages[0]}" ]] && packages=($(ls Packages))
shift || true
for p in "${packages[@]}"; do
  echo "== $p"
  swift test --package-path "Packages/$p" "${flags[@]}" "$@"
done
