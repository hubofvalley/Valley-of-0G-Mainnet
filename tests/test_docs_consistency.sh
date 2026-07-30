#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

validator_bundle=$(jq -r '.components.validator.bundle.version_current' VERSIONS.json)
grep -Fq "| Validator bundle (Aristotle) | ${validator_bundle} |" README.md

python3 - <<'PY'
from pathlib import Path
import re
import sys

root = Path.cwd()
errors = []

for doc in root.rglob("*.md"):
    if ".git" in doc.parts:
        continue
    text = doc.read_text(encoding="utf-8")
    for target in re.findall(r"(?<!!)\[[^\]]+\]\(([^)]+)\)", text):
        target = target.strip().split("#", 1)[0]
        if not target or "://" in target or target.startswith(("mailto:", "#")):
            continue
        target = target.replace("%20", " ")
        resolved = (doc.parent / target).resolve()
        if not resolved.exists():
            errors.append(f"{doc.relative_to(root)}: missing local link {target}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY

echo "Documentation consistency checks passed."
