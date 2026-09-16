#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFEST_LIB="${VALLEY_MANIFEST_LIB:-$SCRIPT_DIR/valley_manifest.sh}"
[ -r "$MANIFEST_LIB" ] || { echo "Valley manifest loader not found: $MANIFEST_LIB" >&2; exit 2; }
# shellcheck source=resources/valley_manifest.sh
source "$MANIFEST_LIB"
valley_manifest_init
TARGET_VERSION=$(valley_manifest_get '.components.storage_node.version_current')
TARGET_COMMIT=$(valley_manifest_get '.components.storage_node.pinned_commit')
valley_require_git_commit "$TARGET_COMMIT" || { echo "Invalid Storage commit in VERSIONS.json." >&2; exit 2; }

NODE_DIR="${ZGS_HOME:-$HOME/0g-storage-node}"
CONFIG_FILE="${ZGS_CONFIG_FILE:-$NODE_DIR/run/config-mainnet.toml}"
SERVICE_NAME="zgs"
[ -d "$NODE_DIR/.git" ] && [ -f "$CONFIG_FILE" ] || { echo "Existing Storage checkout/config not found." >&2; exit 1; }

miner_key_is_configured() {
    awk '
        /^[[:space:]]*miner_key[[:space:]]*=/ {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            sub(/[[:space:]]*#.*/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            if (value != "\"\"" && value != "\047\047") configured = 1
        }
        END { exit(configured ? 0 : 1) }
    ' "$CONFIG_FILE"
}

miner_cpu_zero_is_configured() {
    awk '
        /^[[:space:]]*miner_cpu_percentage[[:space:]]*=/ {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            sub(/[[:space:]]*#.*/, "", value)
            gsub(/[[:space:]_]/, "", value)
            if (value ~ /^[+-]?0$/ || value ~ /^0[xX]0+$/ || value ~ /^0[oO]0+$/ || value ~ /^0[bB]0+$/) zero = 1
        }
        END { exit(zero ? 0 : 1) }
    ' "$CONFIG_FILE"
}

MINER_KEY_CONFIGURED=false
if miner_key_is_configured; then
    MINER_KEY_CONFIGURED=true
    echo "Legacy populated miner_key detected in the existing Storage config."
    echo "Valley will not extract, print, rewrite, copy, or move its value; the existing config is preserved unchanged."
    echo "Upstream Storage currently requires raw key material for mining, so this residual persistent-secret limitation remains operator-owned."
fi

# The managed v1.2.0 release accepts a numeric zero miner_cpu_percentage, but its
# mining loop gates work on cpu_percent > 0. With a miner key configured that
# becomes a silent non-mining state: the process stays up without mining.
# Upstream main now rejects zero, but no newer tagged Storage release contains
# that guard yet. Keep this rule release-bounded so future semantics are not
# guessed. Detect equivalent TOML integer-zero spellings instead of only literal
# "0" so the preflight cannot be bypassed with +0 or a zero-valued base literal.
if [[ "$TARGET_VERSION" == "v1.2.0" && "$MINER_KEY_CONFIGURED" == true ]] && miner_cpu_zero_is_configured; then
    echo "Storage update refused: v1.2.0 silently disables PoRA mining when miner_key is configured and miner_cpu_percentage resolves to 0." >&2
    echo "Set miner_cpu_percentage to 1..100, or remove miner_key if mining is intentionally disabled, then retry." >&2
    exit 1
fi

# Upstream defaults gRPC to 0.0.0.0:50051 when the setting is omitted. Require
# an explicit operator choice before an update can restart the service, so an
# old config cannot silently gain a public listener after a binary upgrade.
if ! grep -Eq '^[[:space:]]*listen_address_grpc[[:space:]]*=[[:space:]]*"[^\"]+"' "$CONFIG_FILE"; then
    echo "Storage update refused: listen_address_grpc is not explicitly configured." >&2
    echo "Upstream defaults the missing setting to 0.0.0.0:50051." >&2
    echo "Set listen_address_grpc under [rpc] explicitly (recommended: 127.0.0.1:50051), review firewall/proxy policy, then retry." >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*listen_address_grpc[[:space:]]*=[[:space:]]*"(0\.0\.0\.0|\[::\]):[0-9]+"' "$CONFIG_FILE"; then
    echo "WARNING: Storage gRPC is explicitly configured on a wildcard/public listener."
    echo "Proceeding because the exposure is explicit; ensure firewall/rate-limit policy is intentional."
fi

cd "$NODE_DIR"
git fetch --all --tags
git checkout --detach "$TARGET_COMMIT"
[ "$(git rev-parse HEAD)" = "$TARGET_COMMIT" ] || { echo "Storage source pin verification failed." >&2; exit 1; }
git submodule update --init --recursive
cargo build --release --locked

sudo systemctl stop "$SERVICE_NAME"
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE_NAME"
systemctl is-active --quiet "$SERVICE_NAME" || { echo "Storage service did not become active after update." >&2; exit 1; }
echo "Storage Node updated to managed target $TARGET_VERSION ($TARGET_COMMIT). Existing config was preserved."
