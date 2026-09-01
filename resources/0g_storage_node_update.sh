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

if grep -Eq '^[[:space:]]*miner_key[[:space:]]*=[[:space:]]*"[^\"]+"' "$CONFIG_FILE"; then
    echo "Legacy populated miner_key detected in the existing Storage config."
    echo "Valley will not read, print, rewrite, copy, or move its value; the existing config is preserved unchanged."
    echo "Upstream Storage currently requires raw key material for mining, so this residual persistent-secret limitation remains operator-owned."
fi

cd "$NODE_DIR"
git fetch --all --tags
git checkout --detach "$TARGET_COMMIT"
[ "$(git rev-parse HEAD)" = "$TARGET_COMMIT" ] || { echo "Storage source pin verification failed." >&2; exit 1; }
git submodule update --init --recursive
cargo build --release

sudo systemctl stop "$SERVICE_NAME"
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE_NAME"
systemctl is-active --quiet "$SERVICE_NAME" || { echo "Storage service did not become active after update." >&2; exit 1; }
echo "Storage Node updated to managed target $TARGET_VERSION ($TARGET_COMMIT). Existing config was preserved."
