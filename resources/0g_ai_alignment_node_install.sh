#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RESET='\033[0m'
APP_DIR="${ALIGNMENT_HOME:-$HOME/0g-alignment-node}"
BIN_NAME="0g-alignment-node"
SERVICE_NAME="0g-alignment-node"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFEST_LIB="${VALLEY_MANIFEST_LIB:-$SCRIPT_DIR/valley_manifest.sh}"
[ -r "$MANIFEST_LIB" ] || { echo "Valley manifest loader not found: $MANIFEST_LIB" >&2; exit 2; }
# shellcheck source=resources/valley_manifest.sh
source "$MANIFEST_LIB"
valley_manifest_init
VERSION=$(valley_manifest_get '.components.ai_alignment_node.version_current')
RELEASE_REF=$(valley_manifest_get '.components.ai_alignment_node.release_ref')
RELEASE_REPO=$(valley_manifest_get '.components.ai_alignment_node.release_repo')
RELEASE_ARTIFACT=$(valley_manifest_get '.components.ai_alignment_node.release_artifact')
RELEASE_SHA256=$(valley_manifest_get '.components.ai_alignment_node.release_artifact_sha256')
valley_require_sha256 "$RELEASE_SHA256" || { echo "Invalid Alignment artifact digest in VERSIONS.json." >&2; exit 2; }
RELEASE_URL="${RELEASE_REPO}/releases/download/${RELEASE_REF}/${RELEASE_ARTIFACT}"

read -r -p "Choose your port (default 8080, e.g. 34567): " NODE_PORT
NODE_PORT=${NODE_PORT:-8080}
read -r -p "Create a staged systemd service unit? (yes/no, default yes): " CREATE_SERVICE
CREATE_SERVICE=${CREATE_SERVICE:-yes}

cat <<EOF_NOTICE
Alignment private-key boundary:
- Official upstream ${VERSION} requires raw service private-key material in config/environment and uses a raw --key argument for register/approve helpers.
- Valley will not collect, persist, echo, or pass that raw key.
- This flow stages only the verified binary, non-secret config, and optionally a disabled service unit.
- Registration, approval, enabling, and startup are intentionally not automated until upstream offers a signer/secret interface that avoids raw key exposure.
EOF_NOTICE
read -r -p "Type STAGE-ALIGNMENT to continue: " confirm
[ "$confirm" = "STAGE-ALIGNMENT" ] || { echo "Alignment staging cancelled."; exit 0; }

for tool in curl sha256sum tar; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required tool missing: $tool" >&2; exit 1; }
done
mkdir -p "$APP_DIR"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
archive="$tmpdir/$RELEASE_ARTIFACT"
curl -fL --retry 3 "$RELEASE_URL" -o "$archive"
printf '%s  %s\n' "$RELEASE_SHA256" "$archive" | sha256sum --check
mkdir -p "$tmpdir/extract"
tar -xzf "$archive" -C "$tmpdir/extract"

binary=$(find "$tmpdir/extract" -type f -name "$BIN_NAME" -print -quit)
[ -n "$binary" ] || { echo "Alignment binary not found in verified artifact." >&2; exit 1; }
install -m 0755 "$binary" "$APP_DIR/$BIN_NAME"

cat > "$APP_DIR/config.toml" <<EOF_CONFIG
ZG_ALIGNMENT_NODE_LOG_LEVEL="info"
ZG_ALIGNMENT_NODE_SERVICE_IP="http://127.0.0.1:${NODE_PORT}"
EOF_CONFIG
chmod 600 "$APP_DIR/config.toml"

if [ "${CREATE_SERVICE,,}" = "yes" ] || [ "${CREATE_SERVICE,,}" = "y" ]; then
    sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" >/dev/null <<EOF_UNIT
[Unit]
Description=0G AI Alignment Node (staged; secret not configured)
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/$BIN_NAME start --mainnet
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF_UNIT
    sudo systemctl daemon-reload
fi

echo -e "${GREEN}Alignment ${VERSION} staged from the verified release artifact.${RESET}"
echo "The service was NOT enabled or started and no registration/approval transaction was submitted."
echo "If you proceed manually, keep any operator-owned secret file mode 0600 and outside logs/source control; Valley does not consume it."
