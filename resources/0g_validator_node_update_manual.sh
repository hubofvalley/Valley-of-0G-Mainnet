#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck disable=SC1090
source "$HOME/.bash_profile" 2>/dev/null || true
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFEST_LIB="${VALLEY_MANIFEST_LIB:-$SCRIPT_DIR/valley_manifest.sh}"
[ -r "$MANIFEST_LIB" ] || { echo "Valley manifest loader not found: $MANIFEST_LIB" >&2; exit 2; }
# shellcheck source=resources/valley_manifest.sh
source "$MANIFEST_LIB"
valley_manifest_init

TARGET_VERSION=$(valley_manifest_get '.components.validator.bundle.version_current')
RELEASE_REF=$(valley_manifest_get '.components.validator.bundle.release_ref')
RELEASE_REPO=$(valley_manifest_get '.components.validator.bundle.release_repo')
ARTIFACT=$(valley_manifest_get '.components.validator.bundle.release_artifact')
ARTIFACT_SHA256=$(valley_manifest_get '.components.validator.bundle.release_artifact_sha256')
valley_require_sha256 "$ARTIFACT_SHA256" || { echo "Invalid Aristotle digest in VERSIONS.json." >&2; exit 2; }
RELEASE_URL="${RELEASE_REPO}/releases/download/${RELEASE_REF}/${ARTIFACT}"

OG_SERVICE_NAME=${OG_SERVICE_NAME:-0gchaind}
OG_GETH_SERVICE_NAME=${OG_GETH_SERVICE_NAME:-0g-geth}
OG_RETH_SERVICE_NAME=${OG_RETH_SERVICE_NAME:-0g-reth}
EXEC_CLIENT=${EXEC_CLIENT:-geth}
case "$EXEC_CLIENT" in
    geth) EL_SERVICE="$OG_GETH_SERVICE_NAME"; EL_SOURCE_NAME=geth; EL_DEST_NAME=0g-geth ;;
    reth) EL_SERVICE="$OG_RETH_SERVICE_NAME"; EL_SOURCE_NAME=reth; EL_DEST_NAME=0g-reth ;;
    *) echo "Unsupported EXEC_CLIENT=$EXEC_CLIENT" >&2; exit 1 ;;
esac

for tool in curl sha256sum tar systemctl; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required tool missing: $tool" >&2; exit 1; }
done

echo "Managed validator target from VERSIONS.json: $TARGET_VERSION"
read -r -p "Update validator binaries to this reviewed target? (yes/no): " confirm
[ "${confirm,,}" = "yes" ] || { echo "Update cancelled."; exit 0; }

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
archive="$tmpdir/$ARTIFACT"
curl -fL --retry 3 "$RELEASE_URL" -o "$archive"
printf '%s  %s\n' "$ARTIFACT_SHA256" "$archive" | sha256sum --check
tar -xzf "$archive" -C "$tmpdir"
source_dir="$tmpdir/aristotle-${TARGET_VERSION}"
[ -x "$source_dir/bin/0gchaind" ] || { echo "Verified bundle lacks 0gchaind." >&2; exit 1; }
[ -x "$source_dir/bin/$EL_SOURCE_NAME" ] || { echo "Verified bundle lacks $EL_SOURCE_NAME." >&2; exit 1; }

backup_dir="$HOME/backups/valley-validator-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"
[ -f "$HOME/go/bin/0gchaind" ] && cp "$HOME/go/bin/0gchaind" "$backup_dir/0gchaind"
[ -f "$HOME/go/bin/$EL_DEST_NAME" ] && cp "$HOME/go/bin/$EL_DEST_NAME" "$backup_dir/$EL_DEST_NAME"

sudo systemctl stop "$OG_SERVICE_NAME"
sudo systemctl stop "$EL_SERVICE"
install -m 0755 "$source_dir/bin/0gchaind" "$HOME/go/bin/0gchaind"
install -m 0755 "$source_dir/bin/$EL_SOURCE_NAME" "$HOME/go/bin/$EL_DEST_NAME"

rollback_binaries() {
    echo "Update failed; restoring previous binaries from $backup_dir" >&2
    [ -f "$backup_dir/0gchaind" ] && install -m 0755 "$backup_dir/0gchaind" "$HOME/go/bin/0gchaind"
    [ -f "$backup_dir/$EL_DEST_NAME" ] && install -m 0755 "$backup_dir/$EL_DEST_NAME" "$HOME/go/bin/$EL_DEST_NAME"
    sudo systemctl restart "$EL_SERVICE" || true
    sudo systemctl restart "$OG_SERVICE_NAME" || true
}

if ! sudo systemctl restart "$EL_SERVICE" || ! systemctl is-active --quiet "$EL_SERVICE"; then
    rollback_binaries
    exit 1
fi
if ! sudo systemctl restart "$OG_SERVICE_NAME" || ! systemctl is-active --quiet "$OG_SERVICE_NAME"; then
    rollback_binaries
    exit 1
fi

echo "Validator binary update completed: $TARGET_VERSION ($EXEC_CLIENT)."
echo "Rollback binaries retained at: $backup_dir"
