#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFEST_LIB="${VALLEY_MANIFEST_LIB:-$SCRIPT_DIR/valley_manifest.sh}"
[ -r "$MANIFEST_LIB" ] || { echo "Valley manifest loader not found: $MANIFEST_LIB" >&2; exit 2; }
# shellcheck source=resources/valley_manifest.sh
source "$MANIFEST_LIB"
valley_manifest_init
TARGET_VERSION=$(valley_manifest_get '.components.storage_kv.version_current')
TARGET_COMMIT=$(valley_manifest_get '.components.storage_kv.pinned_commit')
valley_require_git_commit "$TARGET_COMMIT" || { echo "Invalid Storage KV commit in VERSIONS.json." >&2; exit 2; }

KV_DIR="${ZGS_KV_HOME:-$HOME/0g-storage-kv}"
CONFIG_FILE="${ZGS_KV_CONFIG_FILE:-$KV_DIR/run/config.toml}"
SERVICE_NAME="zgskv"
[ -d "$KV_DIR/.git" ] && [ -f "$CONFIG_FILE" ] || { echo "Existing Storage KV checkout/config not found." >&2; exit 1; }

cd "$KV_DIR"
git fetch --all --tags
git checkout --detach "$TARGET_COMMIT"
[ "$(git rev-parse HEAD)" = "$TARGET_COMMIT" ] || { echo "Storage KV source pin verification failed." >&2; exit 1; }
git submodule update --init --recursive
cargo build --release

sudo systemctl stop "$SERVICE_NAME"
sudo systemctl daemon-reload
sudo systemctl restart "$SERVICE_NAME"
systemctl is-active --quiet "$SERVICE_NAME" || { echo "Storage KV service did not become active after update." >&2; exit 1; }
echo "Storage KV updated to managed target $TARGET_VERSION ($TARGET_COMMIT). Existing config and databases were preserved."
