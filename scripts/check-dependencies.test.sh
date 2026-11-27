#!/usr/bin/env bash
# Tests scripts/check-dependencies.sh against fixture repositories built in a temporary directory.
set -euo pipefail
cd "$(dirname "$0")/.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0
entry='vendored Packages/Zip/Sources/CZip https://github.com/example/zip v1.0 BSD-2-Clause 2026-11-25'

# A fixture repository holding the real script, an allowlist of the given lines and a Swift-only package.
fixture() { # fixture <name> [allowlist line...]
  local repo="$work/$1"
  shift
  mkdir -p "$repo/scripts" "$repo/security" "$repo/Apps" "$repo/Packages/Zip/Sources/Zip"
  cp scripts/check-dependencies.sh "$repo/scripts/"
  printf '%s\n' '# A comment.' "$@" > "$repo/security/dependency-allowlist.txt"
  touch "$repo/Packages/Zip/Sources/Zip/Zip.swift"
  echo "$repo"
}

vendor() { # vendor <repo> <target> <source file under the target>
  mkdir -p "$(dirname "$1/Packages/Zip/Sources/$2/$3")"
  touch "$1/Packages/Zip/Sources/$2/$3"
}

pin() { # pin <repo> <package URL>
  printf '{ "pins" : [ { "identity" : "dep", "location" : "%s" } ] }\n' "$2" > "$1/Packages/Zip/Package.resolved"
}

expect() { # expect pass|fail <name> <repo>
  local want="$1" name="$2" got=pass
  bash "$3/scripts/check-dependencies.sh" >/dev/null 2>&1 || got=fail
  if [[ "$got" == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (wanted $want, got $got)"; failures=$((failures + 1)); fi
}

expect pass "Swift-only packages need no vendored entry" "$(fixture swift-only)"

r="$(fixture listed "$entry")"; vendor "$r" CZip zip.c
expect pass "vendored C sources with their allowlist entry" "$r"

r="$(fixture unlisted)"; vendor "$r" CZip zip.c
expect fail "vendored C sources without an allowlist entry" "$r"

r="$(fixture other-target "${entry/CZip/COther}")"; vendor "$r" CZip zip.c
expect fail "an entry for another target does not cover them" "$r"

r="$(fixture commented-out "# $entry")"; vendor "$r" CZip zip.c
expect fail "a commented-out entry does not count" "$r"

r="$(fixture no-date "${entry% *}")"; vendor "$r" CZip zip.c
expect fail "an entry without its approval date" "$r"

r="$(fixture bad-date "${entry% *} soon")"; vendor "$r" CZip zip.c
expect fail "an entry whose approval date is not a date" "$r"

r="$(fixture nested)"; vendor "$r" CZip src/deep/zip.c
expect fail "C sources nested below the target directory" "$r"

r="$(fixture cpp)"; vendor "$r" CZip zip.cpp
expect fail "C++ sources count as vendored code" "$r"

r="$(fixture pinned-listed https://github.com/example/dep.git)"; pin "$r" https://github.com/example/dep.git
expect pass "a pinned package on the allowlist" "$r"

r="$(fixture pinned-unlisted)"; pin "$r" https://github.com/example/dep.git
expect fail "a pinned package missing from the allowlist" "$r"

[[ $failures -eq 0 ]] && echo "All check-dependencies cases passed." || { echo "$failures check-dependencies case(s) failed."; exit 1; }
