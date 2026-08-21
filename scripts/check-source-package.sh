#!/usr/bin/env bash
set -euo pipefail

forbidden="$(git ls-files | grep -E '(^|/)[^/]+\.(xcframework|framework|dSYM)(/|$)|\.(ipa|dylib|a|zip|tar|tgz|gz)$' || true)"
if [[ -n "${forbidden}" ]]; then
  echo "Source package contains generated binary/archive artifacts:"
  echo "${forbidden}"
  exit 1
fi

max_bytes=$((10 * 1024 * 1024))
while IFS= read -r -d '' path; do
  [[ -f "${path}" ]] || continue
  bytes="$(stat -f '%z' "${path}")"
  if (( bytes > max_bytes )); then
    echo "Tracked source file exceeds 10 MiB: ${path} (${bytes} bytes)"
    exit 1
  fi
done < <(git ls-files -z)

echo "Source package artifact check passed."
