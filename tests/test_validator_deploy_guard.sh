#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WRAPPER="$ROOT/resources/0g_validator_node_aristotle_install.sh"
fail() { echo "VALIDATOR_DEPLOY_GUARD_TEST_FAIL: $*" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A clean HOME must pass the non-mutating preflight test hook.
clean_home="$TMP/clean"
mkdir -p "$clean_home"
out=$(HOME="$clean_home" VALLEY_TEST_ONLY_PREFLIGHT=1 bash "$WRAPPER" 2>&1) || fail "clean preflight should pass"
grep -Fq 'Validator deploy preflight passed' <<<"$out" || fail "clean preflight success marker missing"

# Any existing managed data root must fail closed before the implementation runs.
root_home="$TMP/root"
mkdir -p "$root_home/.0gchaind"
if HOME="$root_home" VALLEY_TEST_ONLY_PREFLIGHT=1 bash "$WRAPPER" >"$TMP/root.out" 2>&1; then
    fail "existing managed data root was accepted"
fi
grep -Fq 'existing managed 0G node data was detected' "$TMP/root.out" || fail "managed-root refusal message missing"

# Consensus key presence must fail regardless of an RPC-mode environment hint.
key_home="$TMP/key"
mkdir -p "$key_home/.0gchaind/0g-home/0gchaind-home/config"
: > "$key_home/.0gchaind/0g-home/0gchaind-home/config/priv_validator_key.json"
if HOME="$key_home" NODE_TYPE=rpc VALLEY_TEST_ONLY_PREFLIGHT=1 bash "$WRAPPER" >"$TMP/key.out" 2>&1; then
    fail "RPC-mode hint bypassed validator-key guard"
fi
grep -Fq 'existing validator signing material was detected' "$TMP/key.out" || fail "validator-key refusal message missing"
grep -Fq 'changing deploy type cannot bypass it' "$TMP/key.out" || fail "RPC-bypass warning missing"

# Last-sign state alone is also sufficient to block the destructive deploy.
state_home="$TMP/state"
mkdir -p "$state_home/.0gchaind/0g-home/0gchaind-home/data"
: > "$state_home/.0gchaind/0g-home/0gchaind-home/data/priv_validator_state.json"
if HOME="$state_home" NODE_TYPE=validator VALLEY_TEST_ONLY_PREFLIGHT=1 bash "$WRAPPER" >"$TMP/state.out" 2>&1; then
    fail "signing-state guard did not fail closed"
fi
grep -Fq 'existing validator signing material was detected' "$TMP/state.out" || fail "signing-state refusal message missing"

# Broken symlink roots are still existing operator-owned paths and must be refused.
link_home="$TMP/link"
mkdir -p "$link_home"
ln -s "$TMP/does-not-exist" "$link_home/.0gchaind"
if HOME="$link_home" VALLEY_TEST_ONLY_PREFLIGHT=1 bash "$WRAPPER" >"$TMP/link.out" 2>&1; then
    fail "broken-symlink data root was accepted"
fi
grep -Fq 'existing managed 0G node data was detected' "$TMP/link.out" || fail "symlink-root refusal message missing"

echo "VALIDATOR_DEPLOY_GUARD_TEST_OK"
