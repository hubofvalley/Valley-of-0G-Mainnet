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
SOURCE_TAG=$(valley_manifest_get '.components.storage_kv.source_tag')
SOURCE_TAG_OBJECT=$(valley_manifest_get '.components.storage_kv.source_tag_object')
RUST_VERSION=$(valley_manifest_get '.components.storage_kv.build_toolchain.rust')
KV_REPO=$(valley_manifest_get '.components.storage_kv.release_repo')
valley_require_git_commit "$TARGET_COMMIT" || { echo "Invalid Storage KV commit in VERSIONS.json." >&2; exit 2; }
valley_require_git_commit "$SOURCE_TAG_OBJECT" || { echo "Invalid Storage KV tag object in VERSIONS.json." >&2; exit 2; }

KV_DIR="${ZGS_KV_HOME:-$HOME/0g-storage-kv}"
CONFIG_FILE="${ZGS_KV_CONFIG_FILE:-$KV_DIR/run/config.toml}"
SERVICE_NAME="${ZGS_KV_SERVICE_NAME:-zgskv}"
BIN_PATH="$KV_DIR/target/release/zgs_kv"

[[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || { echo "Invalid Storage KV service name." >&2; exit 2; }
[ -d "$KV_DIR/.git" ] && [ -f "$CONFIG_FILE" ] || { echo "Existing Storage KV checkout/config not found." >&2; exit 1; }
systemctl cat "$SERVICE_NAME" >/dev/null 2>&1 || { echo "$SERVICE_NAME.service is not installed." >&2; exit 1; }

for tool in git cargo rustc systemctl; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required tool missing: $tool" >&2; exit 2; }
done

if [ -n "$(git -C "$KV_DIR" status --porcelain --untracked-files=no)" ]; then
    echo "Update blocked: tracked local modifications exist in $KV_DIR." >&2
    exit 1
fi

STAGE_ROOT=$(mktemp -d "$HOME/.valley-zgskv-update.XXXXXX")
STAGE_SRC="$STAGE_ROOT/source"
BACKUP_DIR="$KV_DIR/.valley-backups/$(date -u +%Y%m%dT%H%M%SZ)"
trap 'rm -rf "$STAGE_ROOT"' EXIT

echo "Staging and verifying Storage KV $TARGET_VERSION while $SERVICE_NAME remains online..."
git clone --filter=blob:none --no-checkout "${KV_REPO}.git" "$STAGE_SRC"
git -C "$STAGE_SRC" fetch --force origin "refs/tags/${SOURCE_TAG}:refs/tags/${SOURCE_TAG}"
[ "$(git -C "$STAGE_SRC" rev-parse "refs/tags/${SOURCE_TAG}")" = "$SOURCE_TAG_OBJECT" ] || {
    echo "Storage KV tag object verification failed." >&2
    exit 1
}
[ "$(git -C "$STAGE_SRC" rev-parse "refs/tags/${SOURCE_TAG}^{commit}")" = "$TARGET_COMMIT" ] || {
    echo "Storage KV tag-to-commit verification failed." >&2
    exit 1
}
git -C "$STAGE_SRC" checkout --detach "$TARGET_COMMIT"
git -C "$STAGE_SRC" submodule update --init --recursive

[ "$(tr -d '[:space:]' < "$STAGE_SRC/rust-toolchain")" = "$RUST_VERSION" ] || {
    echo "Storage KV rust-toolchain does not match VERSIONS.json." >&2
    exit 1
}
active_rust=$(cd "$STAGE_SRC" && rustc --version | awk '{print $2}')
[ "$active_rust" = "$RUST_VERSION" ] || {
    echo "Rust $RUST_VERSION is required; active version is ${active_rust:-unknown}." >&2
    exit 1
}
(cd "$STAGE_SRC" && cargo build --release --locked)
STAGED_BINARY="$STAGE_SRC/target/release/zgs_kv"
[ -x "$STAGED_BINARY" ] || { echo "Staged Storage KV binary missing." >&2; exit 1; }
"$STAGED_BINARY" --help >/dev/null

# Fetch the exact target into the live checkout before downtime, but do not
# change the checked-out source until the operator crosses the update gate.
git -C "$KV_DIR" fetch origin "$TARGET_COMMIT"

echo "Verified target: $TARGET_VERSION ($TARGET_COMMIT)"
echo "Existing config and databases will be preserved."
read -r -p "Type UPDATE-ZGSKV to replace the managed binary: " UPDATE_CONFIRM
[ "$UPDATE_CONFIRM" = "UPDATE-ZGSKV" ] || { echo "Update cancelled before downtime."; exit 0; }

OLD_COMMIT=$(git -C "$KV_DIR" rev-parse HEAD)
mkdir -p "$BACKUP_DIR"
cp "$CONFIG_FILE" "$BACKUP_DIR/config.toml"
[ -x "$BIN_PATH" ] && cp "$BIN_PATH" "$BACKUP_DIR/zgs_kv"

sudo systemctl stop "$SERVICE_NAME"

rollback() {
    echo "Storage KV update failed; attempting rollback to $OLD_COMMIT." >&2
    git -C "$KV_DIR" checkout --detach "$OLD_COMMIT" >/dev/null 2>&1 || true
    if [ -f "$BACKUP_DIR/zgs_kv" ]; then
        install -m 0755 "$BACKUP_DIR/zgs_kv" "$BIN_PATH" || true
    fi
    cp "$BACKUP_DIR/config.toml" "$CONFIG_FILE" 2>/dev/null || true
    sudo systemctl restart "$SERVICE_NAME" 2>/dev/null || true
}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then rollback; fi; rm -rf "$STAGE_ROOT"; exit "$rc"' EXIT

git -C "$KV_DIR" checkout --detach "$TARGET_COMMIT"
git -C "$KV_DIR" submodule update --init --recursive
mkdir -p "$(dirname "$BIN_PATH")"
install -m 0755 "$STAGED_BINARY" "$BIN_PATH"

sudo systemctl restart "$SERVICE_NAME"
systemctl is-active --quiet "$SERVICE_NAME" || { echo "Storage KV service did not become active." >&2; exit 1; }

trap - EXIT
rm -rf "$STAGE_ROOT"
echo "Storage KV is active on managed target $TARGET_VERSION ($TARGET_COMMIT)."
echo "Rollback backup retained at $BACKUP_DIR"
