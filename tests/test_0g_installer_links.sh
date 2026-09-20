#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

canonical='https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Mainnet/main/resources/valleyof0G.sh'
legacy='https://raw.githubusercontent.com/hubofvalley/Mainnet-Guides/main/0g%20\\(zero-gravity\\)/resources/valleyof0G.sh'
files=(
  docs/ai-alignment-node.md
  docs/snapshots.md
  docs/scheduler.md
  docs/storage-kv.md
  docs/storage-node.md
  docs/validator-node.md
)

for file in "${files[@]}"; do
  test -f "$file"
  test "$(grep -Fc "$canonical" "$file")" -eq 1
  test "$(grep -Fc "$legacy" "$file")" -eq 0
done

if grep -RIlF --include='*.md' "$legacy" docs >/tmp/gv-legacy-0g-links.txt; then
  echo "legacy 0G installer links remain:" >&2
  cat /tmp/gv-legacy-0g-links.txt >&2
  exit 1
fi

echo "0G generated installer link contract: PASS (6 docs use Valley-of-0G-Mainnet)"
