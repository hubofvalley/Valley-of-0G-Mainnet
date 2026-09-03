#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/VERSIONS.json"
fail() { echo "MANIFEST_INTEGRITY_TEST_FAIL: $*" >&2; exit 1; }

jq -e '.network == "0g-mainnet" and .schema_version == "1.1"' "$MANIFEST" >/dev/null || fail "unexpected manifest identity/schema"
jq -e '.chain.consensus_network == "0G-mainnet-aristotle"' "$MANIFEST" >/dev/null || fail "consensus network drift"
jq -e '.chain.evm_default_rpc_port == 8545 and .chain.engine_default_rpc_port == 8551' "$MANIFEST" >/dev/null || fail "execution port defaults drift"
jq -e '.source_of_truth | startswith("VERSIONS.json;")' "$MANIFEST" >/dev/null || fail "VERSIONS.json is not declared authoritative"

[ "$(jq -r '.components.storage_node.version_current' "$MANIFEST")" = 'v1.1.0' ] || fail "Storage managed version drift"
[ "$(jq -r '.components.storage_node.source_tag' "$MANIFEST")" = 'v1.1.0' ] || fail "Storage source tag drift"
[ "$(jq -r '.components.storage_node.pinned_commit' "$MANIFEST")" = 'e41726de7825b9e8e6eeb7802f40308d880089b2' ] || fail "Storage v1.1.0 commit drift"

[ "$(jq -r '.components.storage_kv.version_current' "$MANIFEST")" = 'v1.4.0' ] || fail "Storage KV managed version drift"
[ "$(jq -r '.components.storage_kv.source_tag' "$MANIFEST")" = 'v1.4.0' ] || fail "Storage KV source tag drift"
[ "$(jq -r '.components.storage_kv.pinned_commit' "$MANIFEST")" = '707db658c80aebb9f902152b311a1c26884f9e63' ] || fail "Storage KV v1.4.0 commit drift"
[ "$(jq -r '.components.storage_kv.build_toolchain.rust' "$MANIFEST")" = '1.75.0' ] || fail "Storage KV Rust toolchain drift"
[ "$(jq -r '.components.storage_kv.build_toolchain.cargo_locked' "$MANIFEST")" = 'true' ] || fail "Storage KV build must remain Cargo.lock enforced"
[ "$(jq -r '.components.storage_kv.upstream_latest' "$MANIFEST")" = 'v1.5.1' ] || fail "Storage KV upstream candidate drift"
[ "$(jq -r '.components.storage_kv.upstream_latest_linux_asset_sha256' "$MANIFEST")" = '7e5ef9c83d5907399863a0832c8cc1f42decc6499cedd72e7aadb94822d1e4c6' ] || fail "Storage KV v1.5.1 candidate digest drift"

[ "$(jq -r '.components.validator.bundle.version_current' "$MANIFEST")" = 'v1.0.6' ] || fail "validator target drift"
[ "$(jq -r '.components.validator.bundle.release_artifact_sha256' "$MANIFEST")" = '7de32d15a82009bd7fb0da760c708aa5af55ebfc89ebb11d69cf45548f7ceca9' ] || fail "validator artifact digest drift"
[ "$(jq -r '.components.ai_alignment_node.release_artifact_sha256' "$MANIFEST")" = 'aa515a403ca2ac9d9321166942631ec158eeda822f3fc11263cd3bdb405c74c1' ] || fail "Alignment artifact digest drift"
while IFS= read -r value; do
    [[ "$value" =~ ^[0-9a-f]{40}$ ]] || fail "invalid commit pin: $value"
done < <(jq -r '.components.storage_node.pinned_commit, .components.storage_kv.pinned_commit' "$MANIFEST")
while IFS= read -r value; do
    [[ "$value" =~ ^[0-9a-f]{64}$ ]] || fail "invalid artifact digest: $value"
done < <(jq -r '.components.validator.bundle.release_artifact_sha256, .components.ai_alignment_node.release_artifact_sha256' "$MANIFEST")

# Covered managed flows must consume the manifest instead of mutable branches,
# latest tool selectors, or the known incorrect old KV pin.
covered=(
    resources/0g_validator_node_aristotle_install.sh
    resources/0g_validator_node_update_manual.sh
    resources/0g_geth_to_reth_migrate.sh
    resources/0gchain_app_install.sh
    resources/0g_storage_node_install.sh
    resources/0g_storage_node_update.sh
    resources/0g_storage_kv_install.sh
    resources/0g_storage_kv_update.sh
    resources/0g_ai_alignment_node_install.sh
)
for rel in "${covered[@]}"; do
    file="$ROOT/$rel"
    grep -Fq 'valley_manifest_get' "$file" || fail "$rel does not consume VERSIONS.json"
done

if grep -RInE --include='*.sh' 'git[[:space:]]+checkout[[:space:]]+main|git[[:space:]]+clone[[:space:]]+-b|@latest|99c91d95a1d664ffdc9700ef492a00bd76c9c5d1' "$ROOT/resources"; then
    fail "mutable/incorrect version selector remains in resources"
fi

for rel in \
    resources/0g_validator_node_aristotle_install.sh \
    resources/0g_validator_node_update_manual.sh \
    resources/0g_geth_to_reth_migrate.sh \
    resources/0gchain_app_install.sh \
    resources/0g_ai_alignment_node_install.sh; do
    grep -Fq 'sha256sum --check' "$ROOT/$rel" || fail "$rel does not verify release digest"
done
for rel in \
    resources/0g_storage_node_install.sh \
    resources/0g_storage_node_update.sh \
    resources/0g_storage_kv_install.sh \
    resources/0g_storage_kv_update.sh; do
    grep -Fq 'checkout --detach "$TARGET_COMMIT"' "$ROOT/$rel" || fail "$rel does not checkout detached manifest commit"
    grep -Fq 'rev-parse HEAD' "$ROOT/$rel" || fail "$rel does not verify checked-out commit"
done

for rel in \
    resources/0g_storage_kv_install.sh \
    resources/0g_storage_kv_update.sh; do
    grep -Fq 'cargo build --release --locked' "$ROOT/$rel" || fail "$rel does not enforce Cargo.lock"
    grep -Fq '.components.storage_kv.source_tag_object' "$ROOT/$rel" || fail "$rel does not verify the reviewed tag object"
done

# User-facing version table remains mechanically aligned with the manifest.
grep -Fq "| Validator bundle (Aristotle) | $(jq -r '.components.validator.bundle.version_current' "$MANIFEST") |" "$ROOT/README.md" || fail "README validator version drift"
grep -Fq "| Storage Node | $(jq -r '.components.storage_node.version_current' "$MANIFEST") |" "$ROOT/README.md" || fail "README Storage version drift"
grep -Fq "| Storage KV | $(jq -r '.components.storage_kv.version_current' "$MANIFEST") |" "$ROOT/README.md" || fail "README KV version drift"

echo "MANIFEST_INTEGRITY_TEST_OK"
