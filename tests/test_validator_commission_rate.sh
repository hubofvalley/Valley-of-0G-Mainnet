#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/resources/valleyof0G.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "not ok - $*" >&2; exit 1; }
contains() { grep -Fq "$2" "$1" || fail "$1 does not contain: $2"; }

awk '
  /^function staking_rewards_percent_to_ppm\(\)/ { capture = 1 }
  capture { print }
  capture && /^}$/ { exit }
' "$SCRIPT" > "$TMP/function.sh"

# shellcheck source=/dev/null
source "$TMP/function.sh"

assert_ppm() {
  local input=$1 expected=$2 actual
  actual=$(staking_rewards_percent_to_ppm "$input") || fail "$input was rejected"
  [ "$actual" = "$expected" ] || fail "$input converted to $actual, expected $expected"
}

assert_invalid() {
  local input=$1
  if staking_rewards_percent_to_ppm "$input" >/dev/null 2>&1; then
    fail "invalid percentage was accepted: $input"
  fi
}

assert_ppm 0 0
assert_ppm 1 10000
assert_ppm 5 50000
assert_ppm 5.25 52500
assert_ppm 0.0001 1
assert_ppm 99.9999 999999
assert_ppm 100 1000000
assert_ppm 100.0000 1000000

for invalid in "" -1 +1 1e2 1.00001 99.99999 100.0001 101 abc "5%"; do
  assert_invalid "$invalid"
done

contains "$SCRIPT" '8) Change validator commission rate (operator only)'
contains "$SCRIPT" "'commissionRate()(uint32)'"
contains "$SCRIPT" "'operatorAddress()(address)'"
contains "$SCRIPT" "'setCommissionRate(uint32)'"
contains "$SCRIPT" 'Submit commission rate change? (y/n, b=back):'
contains "$SCRIPT" 'New commission rate matches the current rate. Nothing to change.'
contains "$SCRIPT" 'commissionRate_ = $new_rate_ppm (ppm, equal to ${new_rate_percent}%)'

if grep -Fq 'Commission (bps)' "$SCRIPT" || grep -Fq 'commissionRate (bps)' "$SCRIPT"; then
  fail "commission rate is still labelled as bps"
fi

echo "ok - validator commission rate conversion and transaction guards"
