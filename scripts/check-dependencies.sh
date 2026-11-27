#!/usr/bin/env bash
# Fails if any Swift package or app project pins a dependency that is not on the Lead-approved allowlist, or if any
# package target holds C-family sources (vendored code) without a `vendored` line for that target on the allowlist.
set -euo pipefail
cd "$(dirname "$0")/.."

allowlist=security/dependency-allowlist.txt
status=0
while IFS= read -r resolved; do
  for url in $(grep -o '"location" *: *"[^"]*"' "$resolved" | sed 's/.*"\([^"]*\)"$/\1/'); do
    if ! grep -qxF "$url" <(grep -v '^#' "$allowlist"); then
      echo "::error file=$resolved::$url is not in $allowlist (needs Lead approval and a permissive licence)"
      status=1
    fi
  done
done < <(find Packages Apps -name Package.resolved -not -path '*/.build/*')

date='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
shopt -s nullglob
for target in Packages/*/Sources/*/; do
  target="${target%/}"
  [[ -n "$(find "$target" -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.m' \
    -o -name '*.mm' \) -print -quit)" ]] || continue
  if ! awk -v t="$target" '$1 == "vendored" && $2 == t && NF == 6 && $3 ~ /^https:\/\// && $6 ~ /^'"$date"'$/ { found = 1 }
      END { exit !found }' "$allowlist"; then
    echo "::error file=$target::$target holds C sources but $allowlist has no line" \
      "'vendored $target <upstream URL> <release> <licence> <approval date>' (needs Lead approval)"
    status=1
  fi
done
[[ $status -eq 0 ]] && echo "All dependencies are on the allowlist."
exit $status
