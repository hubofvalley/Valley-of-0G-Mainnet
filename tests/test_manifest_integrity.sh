#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/VERSIONS.json"
fail() { echo "MANIFEST_INTEGRITY_TEST_FAIL: $*" >&2; exit 1; }

jq -e '.network == "0g-mainnet" and .schema_version == "1.1"' "$MANIFEST" >/dev/null || fail "unexpected manifest identity/schema"
jq -e '.chain.consensus_network == "0G-mainnet-aristotle"' "$MANIFEST" >/dev/null || fail "consensus network drift"
jq -e '.chain.evm_default_rpc_port == 8545 and .chain.engine_default_rpc_port == 8551' "$MANIFEST" >/dev/null || fail "execution port defaults drift"
jq -e '.source_of_truth | startswith("VERSIONS.json;")' "$MANIFEST" >/dev/null || fail "VERSIONS.json is not declared authoritative"

[ "$(jq -r '.components.storage_node.version_current' "$MANIFEST")" = 'v1.2.0' ] || fail "Storage managed version drift"
[ "$(jq -r '.components.storage_node.source_tag' "$MANIFEST")" = 'v1.2.0' ] || fail "Storage source tag drift"
[ "$(jq -r '.components.storage_node.source_tag_object' "$MANIFEST")" = '0445ef6a3a403468f14a4ce654bc2ecb0cfe9acc' ] || fail "Storage v1.2.0 tag ref drift"
[ "$(jq -r '.components.storage_node.pinned_commit' "$MANIFEST")" = '0445ef6a3a403468f14a4ce654bc2ecb0cfe9acc' ] || fail "Storage v1.2.0 commit drift"
[ "$(jq -r '.components.storage_node.config_source.path' "$MANIFEST")" = 'run/config-mainnet-turbo.toml' ] || fail "Storage mainnet config path drift"
[ "$(jq -r '.components.storage_node.config_source.commit' "$MANIFEST")" = '0445ef6a3a403468f14a4ce654bc2ecb0cfe9acc' ] || fail "Storage mainnet config commit drift"
[ "$(jq -r '.components.storage_node.config_source.blob_sha' "$MANIFEST")" = '1b7abfc8029867f442f6131c7acf3f1ea4b85a95' ] || fail "Storage mainnet config blob drift"
jq -e '.components.storage_node.config_source.commit == .components.storage_node.pinned_commit' "$MANIFEST" >/dev/null || fail "Storage binary/config commits must stay coherent"
[ "$(jq -r '.components.storage_node.upstream_latest' "$MANIFEST")" = 'v1.2.0' ] || fail "Storage upstream version drift"
[ "$(jq -r '.components.storage_node.upgrade_status' "$MANIFEST")" = 'current_needs_live_verification' ] || fail "Storage live-verification status drift"
[ "$(jq -r '.components.storage_node.needs_live_verification' "$MANIFEST")" = 'true' ] || fail "Storage must remain marked for live validation"

[ "$(jq -r '.components.storage_kv.version_current' "$MANIFEST")" = 'v1.4.0' ] || fail "Storage KV managed version drift"
[ "$(jq -r '.components.storage_kv.source_tag' "$MANIFEST")" = 'v1.4.0' ] || fail "Storage KV source tag drift"
[ "$(jq -r '.components.storage_kv.pinned_commit' "$MANIFEST")" = '707db658c80aebb9f902152b311a1c26884f9e63' ] || fail "Storage KV v1.4.0 commit drift"
[ "$(jq -r '.components.storage_kv.build_toolchain.rust' "$MANIFEST")" = '1.75.0' ] || fail "Storage KV Rust toolchain drift"
[ "$(jq -r '.components.storage_kv.build_toolchain.cargo_locked' "$MANIFEST")" = 'true' ] || fail "Storage KV build must remain Cargo.lock enforced"
[ "$(jq -r '.components.storage_kv.upstream_latest' "$MANIFEST")" = 'v1.5.1' ] || fail "Storage KV upstream candidate drift"
[ "$(jq -r '.components.storage_kv.upstream_latest_linux_asset_sha256' "$MANIFEST")" = '7e5ef9c83d5907399863a0832c8cc1f42decc6499cedd72e7aadb94822d1e4c6' ] || fail "Storage KV v1.5.1 candidate digest drift"

[ "$(jq -r '.components.validator.bundle.version_current' "$MANIFEST")" = 'v1.0.6' ] || fail "validator target drift"
[ "$(jq -r '.components.validator.bundle.upstream_latest' "$MANIFEST")" = 'v1.0.7' ] || fail "validator upstream candidate drift"
[ "$(jq -r '.components.validator.bundle.upstream_latest_release_artifact_sha256' "$MANIFEST")" = '18146c31461be86537a6ad99106021b1a21e73ed62431b0ddfccbe9da0775cdb' ] || fail "validator v1.0.7 candidate digest drift"
[ "$(jq -r '.components.validator.bundle.upgrade_status' "$MANIFEST")" = 'review_required' ] || fail "validator upgrade review status drift"
[ "$(jq -r '.components.validator.bundle.release_artifact_sha256' "$MANIFEST")" = '7de32d15a82009bd7fb0da760c708aa5af55ebfc89ebb11d69cf45548f7ceca9' ] || fail "validator artifact digest drift"
[ "$(jq -r '.components.ai_alignment_node.release_artifact_sha256' "$MANIFEST")" = 'aa515a403ca2ac9d9321166942631ec158eeda822f3fc11263cd3bdb405c74c1' ] || fail "Alignment artifact digest drift"
while IFS= read -r value; do
    [[ "$value" =~ ^[0-9a-f]{40}$ ]] || fail "invalid commit pin: $value"
done < <(jq -r '.components.storage_node.source_tag_object, .components.storage_node.pinned_commit, .components.storage_node.config_source.commit, .components.storage_node.config_source.blob_sha, .components.storage_kv.pinned_commit' "$MANIFEST")
while IFS= read -r value; do
    [[ "$value" =~ ^[0-9a-f]{64}$ ]] || fail "invalid artifact digest: $value"
done < <(jq -r '.components.validator.bundle.release_artifact_sha256, .components.validator.bundle.upstream_latest_release_artifact_sha256, .components.ai_alignment_node.release_artifact_sha256' "$MANIFEST")

# Covered managed flows must consume the manifest instead of mutable branches,
# latest tool selectors, or the known incorrect old KV pin. The public validator
# deploy path is now a safety wrapper; its internal implementation is the
# manifest-consuming artifact installer.
covered=(
    resources/0g_validator_node_aristotle_install_impl.sh
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

VALIDATOR_WRAPPER="$ROOT/resources/0g_validator_node_aristotle_install.sh"
VALIDATOR_IMPL="$ROOT/resources/0g_validator_node_aristotle_install_impl.sh"
grep -Fq 'IMPL_NAME="0g_validator_node_aristotle_install_impl.sh"' "$VALIDATOR_WRAPPER" || fail "validator deploy wrapper does not name its reviewed implementation"
grep -Fq 'exec bash "$LOCAL_IMPL" "$@"' "$VALIDATOR_WRAPPER" || fail "validator deploy wrapper does not execute the local implementation"
grep -Fq 'VALLEY_SOURCE_REF="${VALLEY_SOURCE_REF:-main}"' "$VALIDATOR_WRAPPER" || fail "validator deploy wrapper does not preserve source-ref selection for remote mode"
grep -Fq 'bash "$TMP_IMPL" "$@"' "$VALIDATOR_WRAPPER" || fail "validator deploy wrapper does not execute the remote implementation"
grep -Fq 'valley_manifest_get' "$VALIDATOR_IMPL" || fail "validator implementation does not consume VERSIONS.json"

STORAGE_INSTALL="$ROOT/resources/0g_storage_node_install.sh"
STORAGE_UPDATE="$ROOT/resources/0g_storage_node_update.sh"
grep -Fq '.components.storage_node.source_tag_object' "$STORAGE_INSTALL" || fail "Storage installer does not verify the reviewed tag ref"
grep -Fq '.components.storage_node.config_source.commit' "$STORAGE_INSTALL" || fail "Storage installer does not consume the config commit pin"
grep -Fq '.components.storage_node.config_source.blob_sha' "$STORAGE_INSTALL" || fail "Storage installer does not consume the config blob pin"
grep -Fq 'rev-parse "${CONFIG_SOURCE_COMMIT}:${CONFIG_SOURCE_PATH}"' "$STORAGE_INSTALL" || fail "Storage installer does not verify the config Git blob"
grep -Fq 'show "${CONFIG_SOURCE_COMMIT}:${CONFIG_SOURCE_PATH}" > "$STAGED_CONFIG"' "$STORAGE_INSTALL" || fail "Storage installer does not extract the reviewed config artifact"
grep -Fq 'listen_address_grpc = "127.0.0.1:50051"' "$STORAGE_INSTALL" || fail "Storage installer does not pin gRPC to loopback by default"
grep -Fq 'listen_address_grpc is not explicitly configured' "$STORAGE_UPDATE" || fail "Storage updater does not fail closed on implicit gRPC exposure"

config_verify_line=$(grep -n 'Storage mainnet config artifact verification failed' "$STORAGE_INSTALL" | head -n1 | cut -d: -f1)
apt_line=$(grep -n 'sudo apt-get update -y' "$STORAGE_INSTALL" | head -n1 | cut -d: -f1)
build_line=$(grep -n 'cargo build --release --locked' "$STORAGE_INSTALL" | head -n1 | cut -d: -f1)
move_line=$(grep -n 'mv "$STAGE_SRC" "$NODE_DIR"' "$STORAGE_INSTALL" | head -n1 | cut -d: -f1)
[ "$config_verify_line" -lt "$apt_line" ] || fail "Storage config pin must be verified before OS package mutation"
[ "$apt_line" -lt "$build_line" ] || fail "Storage build ordering is unexpected"
[ "$build_line" -lt "$move_line" ] || fail "Storage checkout is installed before the verified build is ready"

if grep -RInE --include='*.sh' 'git[[:space:]]+checkout[[:space:]]+main|git[[:space:]]+clone[[:space:]]+-b|@latest|99c91d95a1d664ffdc9700ef492a00bd76c9c5d1' "$ROOT/resources"; then
    fail "mutable/incorrect version selector remains in resources"
fi

for rel in \
    resources/0g_validator_node_aristotle_install_impl.sh \
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
    resources/0g_storage_node_install.sh \
    resources/0g_storage_node_update.sh \
    resources/0g_storage_kv_install.sh \
    resources/0g_storage_kv_update.sh; do
    grep -Fq 'cargo build --release --locked' "$ROOT/$rel" || fail "$rel does not enforce Cargo.lock"
done
for rel in \
    resources/0g_storage_kv_install.sh \
    resources/0g_storage_kv_update.sh; do
    grep -Fq '.components.storage_kv.source_tag_object' "$ROOT/$rel" || fail "$rel does not verify the reviewed tag object"
done

# User-facing version table remains mechanically aligned with the manifest.
grep -Fq "| Validator bundle (Aristotle) | $(jq -r '.components.validator.bundle.version_current' "$MANIFEST") |" "$ROOT/README.md" || fail "README validator version drift"
grep -Fq "| Storage Node | $(jq -r '.components.storage_node.version_current' "$MANIFEST") |" "$ROOT/README.md" || fail "README Storage version drift"
grep -Fq "| Storage KV | $(jq -r '.components.storage_kv.version_current' "$MANIFEST") |" "$ROOT/README.md" || fail "README KV version drift"

echo "MANIFEST_INTEGRITY_TEST_OK"
