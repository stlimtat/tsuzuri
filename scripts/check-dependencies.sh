#!/usr/bin/env bash
# Fails if any Swift package or app project pins a dependency that is not on the Lead-approved allowlist.
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
[[ $status -eq 0 ]] && echo "All dependencies are on the allowlist."
exit $status
