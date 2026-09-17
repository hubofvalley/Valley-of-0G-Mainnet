#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MENU="$ROOT/resources/valleyof0G.sh"

fail() { echo "JOURNALCTL_PORTABILITY_TEST_FAIL: $*" >&2; exit 1; }

if grep -RInE --include='*.sh' 'journalctl.*[[:space:]]-fn([[:space:]]|$)' "$ROOT/resources"; then
    fail "found grouped -fn journalctl flags; use explicit long options"
fi

if grep -RInE --include='*.sh' 'journalctl.*[[:space:]]-u([[:space:]]|$)' "$ROOT/resources"; then
    fail "found short -u journalctl flags; use --unit= to bind service names safely"
fi

grep -Fq 'sudo journalctl --unit="$OG_SERVICE_NAME" --unit="$el_svc" --lines=100 --follow --output=cat || true' "$MENU" \
    || fail "combined validator log viewer is not using portable explicit options"
grep -Fq 'sudo journalctl --unit="$OG_SERVICE_NAME" --lines=100 --follow --no-pager || true' "$MENU" \
    || fail "consensus log viewer is not using portable explicit options"
grep -Fq 'sudo journalctl --unit="$el_svc" --lines=100 --follow --no-pager || true' "$MENU" \
    || fail "execution log viewer is not using portable explicit options"
grep -Fq 'sudo journalctl --unit=zgskv --lines=100 --follow --no-pager || true' "$MENU" \
    || fail "Storage KV log viewer is not using portable explicit options"
grep -Fq 'sudo journalctl --unit=0g-alignment-node --lines=100 --follow --no-pager || true' "$MENU" \
    || fail "AI Alignment log viewer is not using portable explicit options"

grep -Fq 'Invalid systemd service name in profile/input.' "$MENU" \
    || fail "mainnet menu does not reject malformed service names"
grep -Fq 'Unsupported EXEC_CLIENT=$EXEC_CLIENT; expected geth or reth.' "$MENU" \
    || fail "mainnet menu does not reject unsupported execution-client values"

echo "JOURNALCTL_PORTABILITY_TEST_OK"
