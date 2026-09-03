#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/resources/0g_storage_kv_install.sh"
UPDATER="$ROOT/resources/0g_storage_kv_update.sh"
MANIFEST="$ROOT/VERSIONS.json"

fail() { echo "STORAGE_KV_HARDENING_TEST_FAIL: $*" >&2; exit 1; }

grep -Fq "EXPECTED_CHAIN_ID=\$(valley_manifest_get '.chain.evm_chain_id')" "$INSTALLER" || fail "installer does not source chain ID from manifest"
grep -Fq 'eth_chainId' "$INSTALLER" || fail "installer does not verify RPC chain identity"
grep -Fq 'RPC rejected:' "$INSTALLER" || fail "wrong-chain RPC does not fail closed"
grep -Fq 'Fresh Storage KV install blocked:' "$INSTALLER" || fail "existing-instance guard missing"
grep -Fq 'refs/tags/${SOURCE_TAG}^{commit}' "$INSTALLER" || fail "installer does not verify peeled tag commit"
grep -Fq 'cargo build --release --locked' "$INSTALLER" || fail "installer does not enforce Cargo.lock"
grep -Fq 'Type ACTIVATE-ZGSKV' "$INSTALLER" || fail "explicit activation gate missing"
grep -Fq 'RPC_LISTEN_ADDRESS="127.0.0.1:6789"' "$INSTALLER" || fail "fresh KV RPC must default to loopback"
grep -Fq 'Upstream v1.5.1 remains review_required' "$INSTALLER" || fail "candidate release boundary is not explicit"

if grep -Eq 'golang\.org/dl|go[0-9.]+\.linux-amd64|sh\.rustup\.rs|curl[^\n]*\|[[:space:]]*(sh|bash)' "$INSTALLER"; then
    fail "installer still contains mutable Go/Rust bootstrap execution"
fi
if grep -Fq '.bash_profile' "$INSTALLER"; then
    fail "installer should not persist runtime configuration into .bash_profile"
fi

guard_line=$(grep -n 'Fresh Storage KV install blocked:' "$INSTALLER" | head -n1 | cut -d: -f1)
clone_line=$(grep -n 'git clone --filter=blob:none' "$INSTALLER" | head -n1 | cut -d: -f1)
activate_line=$(grep -n 'Type ACTIVATE-ZGSKV' "$INSTALLER" | head -n1 | cut -d: -f1)
enable_line=$(grep -n 'systemctl enable --now' "$INSTALLER" | head -n1 | cut -d: -f1)
[ "$guard_line" -lt "$clone_line" ] || fail "existing-instance guard must run before staging source"
[ "$activate_line" -lt "$enable_line" ] || fail "service activation occurs before typed approval"

grep -Fq 'while $SERVICE_NAME remains online' "$UPDATER" || fail "updater does not stage before downtime"
grep -Fq 'cargo build --release --locked' "$UPDATER" || fail "updater does not enforce Cargo.lock"
grep -Fq 'Type UPDATE-ZGSKV' "$UPDATER" || fail "update gate missing"
grep -Fq 'attempting rollback' "$UPDATER" || fail "updater rollback path missing"

build_line=$(grep -n 'cargo build --release --locked' "$UPDATER" | head -n1 | cut -d: -f1)
stop_line=$(grep -n 'systemctl stop "$SERVICE_NAME"' "$UPDATER" | head -n1 | cut -d: -f1)
[ "$build_line" -lt "$stop_line" ] || fail "updater stops service before verified build is ready"

[ "$(jq -r '.components.storage_kv.upgrade_status' "$MANIFEST")" = 'review_required' ] || fail "v1.5.1 must not be auto-promoted"
[ "$(jq -r '.components.storage_kv.version_current' "$MANIFEST")" = 'v1.4.0' ] || fail "managed KV target unexpectedly changed"

echo "STORAGE_KV_HARDENING_TEST_OK"
