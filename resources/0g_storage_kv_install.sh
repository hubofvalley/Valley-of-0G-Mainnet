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
EXPECTED_CHAIN_ID=$(valley_manifest_get '.chain.evm_chain_id')

valley_require_git_commit "$TARGET_COMMIT" || { echo "Invalid Storage KV commit in VERSIONS.json." >&2; exit 2; }
valley_require_git_commit "$SOURCE_TAG_OBJECT" || { echo "Invalid Storage KV tag object in VERSIONS.json." >&2; exit 2; }
[[ "$EXPECTED_CHAIN_ID" =~ ^[0-9]+$ ]] || { echo "Invalid EVM chain ID in VERSIONS.json." >&2; exit 2; }
[[ "$RUST_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid Rust version in VERSIONS.json." >&2; exit 2; }

KV_DIR="${ZGS_KV_HOME:-$HOME/0g-storage-kv}"
SERVICE_NAME="${ZGS_KV_SERVICE_NAME:-zgskv}"
LOG_CONTRACT_ADDRESS="0x62D4144dB0F0a6fBBaeb6296c785C71B3D57C526"
DEFAULT_SYNC_BLOCK="326165"

validate_service_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9_.@-]+$ ]]
}

rpc_result() {
    local endpoint=$1 method=$2
    curl -fsS --connect-timeout 4 --max-time 10 \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":[],\"id\":1}" \
        "$endpoint" 2>/dev/null | jq -r '.result // empty' 2>/dev/null || true
}

hex_to_dec() {
    local value=$1
    if [[ "$value" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf '%d\n' "$((16#${value#0x}))"
    elif [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$value"
    fi
}

validate_rpc_endpoint() {
    local endpoint=$1 chain_raw chain_id block_raw block_number
    [[ "$endpoint" =~ ^https?://[^[:space:]\"]+$ ]] || {
        echo "RPC endpoint must be a non-whitespace http(s) URL." >&2
        return 1
    }
    chain_raw=$(rpc_result "$endpoint" eth_chainId)
    chain_id=$(hex_to_dec "$chain_raw")
    [ "$chain_id" = "$EXPECTED_CHAIN_ID" ] || {
        echo "RPC rejected: $endpoint reports chain ${chain_id:-unavailable}; expected $EXPECTED_CHAIN_ID." >&2
        return 1
    }
    block_raw=$(rpc_result "$endpoint" eth_blockNumber)
    block_number=$(hex_to_dec "$block_raw")
    [[ "$block_number" =~ ^[0-9]+$ ]] || {
        echo "RPC rejected: $endpoint did not return a usable block number." >&2
        return 1
    }
    printf '%s\n' "$block_number"
}

validate_storage_urls() {
    local list=$1 url
    IFS=',' read -r -a urls <<<"$list"
    [ "${#urls[@]}" -gt 0 ] || return 1
    for url in "${urls[@]}"; do
        [[ "$url" =~ ^https?://[^[:space:],\"]+$ ]] || return 1
    done
}

escape_sed_replacement() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//&/\\&}
    value=${value//|/\\|}
    printf '%s' "$value"
}

set_toml_string() {
    local file=$1 key=$2 value=$3 escaped
    escaped=$(escape_sed_replacement "$value")
    sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=.*|${key} = \"${escaped}\"|" "$file"
}

set_toml_number() {
    local file=$1 key=$2 value=$3
    sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
}

for tool in curl jq git cargo rustc systemctl sed grep; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Required tool missing: $tool" >&2
        if [ "$tool" = cargo ] || [ "$tool" = rustc ]; then
            echo "Install Rust via a reviewed method first; Valley will not execute a mutable rustup bootstrap script." >&2
        fi
        exit 2
    }
done

validate_service_name "$SERVICE_NAME" || { echo "Invalid Storage KV service name: $SERVICE_NAME" >&2; exit 2; }

# Fresh-install boundary: do not overwrite an existing checkout or service.
if [ -e "$KV_DIR" ] || systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
    echo "Fresh Storage KV install blocked: existing checkout or $SERVICE_NAME.service detected." >&2
    echo "Use the managed Storage KV update path instead." >&2
    exit 1
fi

read -r -p "Enter storage node URLs (comma-separated, e.g. http://127.0.0.1:5678,http://127.0.0.1:5679): " ZGS_NODE
validate_storage_urls "$ZGS_NODE" || { echo "Invalid Storage node URL list." >&2; exit 1; }

echo "Choose your mainnet JSON-RPC endpoint:"
echo "1) Enter your own endpoint"
echo "2) Grand Valley public endpoint"
echo "3) Official 0G endpoint"
while true; do
    read -r -p "Enter 1, 2, or 3: " RPC_CHOICE
    case "$RPC_CHOICE" in
        1)
            read -r -p "Enter your JSON-RPC endpoint: " BLOCKCHAIN_RPC_ENDPOINT
            ;;
        2)
            BLOCKCHAIN_RPC_ENDPOINT="https://lightnode-json-rpc-mainnet-0g.grandvalleys.com"
            ;;
        3)
            BLOCKCHAIN_RPC_ENDPOINT="https://evmrpc.0g.ai"
            ;;
        *)
            echo "Invalid choice."
            continue
            ;;
    esac
    if BLOCK_NUMBER=$(validate_rpc_endpoint "$BLOCKCHAIN_RPC_ENDPOINT"); then
        echo "RPC verified: chain ID $EXPECTED_CHAIN_ID, latest block $BLOCK_NUMBER."
        break
    fi
    echo "Choose a different RPC endpoint."
done

read -r -p "Log sync start block [default: $DEFAULT_SYNC_BLOCK]: " ZGS_LOG_SYNC_BLOCK
ZGS_LOG_SYNC_BLOCK=${ZGS_LOG_SYNC_BLOCK:-$DEFAULT_SYNC_BLOCK}
[[ "$ZGS_LOG_SYNC_BLOCK" =~ ^[0-9]+$ ]] || { echo "Log sync start block must be an integer." >&2; exit 1; }

RPC_LISTEN_ADDRESS="127.0.0.1:6789"
read -r -p "Expose Storage KV RPC publicly on 0.0.0.0:6789? (y/N): " PUBLIC_RPC
if [[ "$PUBLIC_RPC" =~ ^[Yy]$ ]]; then
    RPC_LISTEN_ADDRESS="0.0.0.0:6789"
fi

STAGE_ROOT=$(mktemp -d "$HOME/.valley-zgskv-stage.XXXXXX")
STAGE_SRC="$STAGE_ROOT/source"
trap 'rm -rf "$STAGE_ROOT"' EXIT

echo "Staging Storage KV $TARGET_VERSION from immutable source before activation..."
git clone --filter=blob:none --no-checkout "${KV_REPO}.git" "$STAGE_SRC"
git -C "$STAGE_SRC" fetch --force origin "refs/tags/${SOURCE_TAG}:refs/tags/${SOURCE_TAG}"

actual_tag_object=$(git -C "$STAGE_SRC" rev-parse "refs/tags/${SOURCE_TAG}")
actual_tag_commit=$(git -C "$STAGE_SRC" rev-parse "refs/tags/${SOURCE_TAG}^{commit}")
[ "$actual_tag_object" = "$SOURCE_TAG_OBJECT" ] || {
    echo "Storage KV tag object verification failed." >&2
    exit 1
}
[ "$actual_tag_commit" = "$TARGET_COMMIT" ] || {
    echo "Storage KV tag-to-commit verification failed." >&2
    exit 1
}

git -C "$STAGE_SRC" checkout --detach "$TARGET_COMMIT"
[ "$(git -C "$STAGE_SRC" rev-parse HEAD)" = "$TARGET_COMMIT" ] || {
    echo "Storage KV source pin verification failed." >&2
    exit 1
}
git -C "$STAGE_SRC" submodule update --init --recursive

stage_toolchain=$(tr -d '[:space:]' < "$STAGE_SRC/rust-toolchain")
[ "$stage_toolchain" = "$RUST_VERSION" ] || {
    echo "Storage KV rust-toolchain drift: source requests ${stage_toolchain:-missing}, manifest requires $RUST_VERSION." >&2
    exit 1
}
active_rust=$(cd "$STAGE_SRC" && rustc --version | awk '{print $2}')
[ "$active_rust" = "$RUST_VERSION" ] || {
    echo "Rust $RUST_VERSION is required for the managed Storage KV build; active version is ${active_rust:-unknown}." >&2
    exit 1
}

echo "Installing OS build dependencies only after source/network preflight passed..."
sudo apt-get update -y
sudo apt-get install -y clang cmake build-essential git libssl-dev pkg-config protobuf-compiler llvm llvm-dev ca-certificates

(cd "$STAGE_SRC" && cargo build --release --locked)
STAGED_BINARY="$STAGE_SRC/target/release/zgs_kv"
[ -x "$STAGED_BINARY" ] || { echo "Storage KV build did not produce zgs_kv." >&2; exit 1; }
"$STAGED_BINARY" --help >/dev/null

STAGED_CONFIG="$STAGE_SRC/run/config.toml"
cp "$STAGE_SRC/run/config_example.toml" "$STAGED_CONFIG"
set_toml_string "$STAGED_CONFIG" rpc_listen_address "$RPC_LISTEN_ADDRESS"
set_toml_string "$STAGED_CONFIG" db_dir "db"
set_toml_string "$STAGED_CONFIG" kv_db_dir "kv.DB"
set_toml_string "$STAGED_CONFIG" log_config_file "log_config"
set_toml_string "$STAGED_CONFIG" log_contract_address "$LOG_CONTRACT_ADDRESS"
set_toml_string "$STAGED_CONFIG" zgs_node_urls "$ZGS_NODE"
set_toml_number "$STAGED_CONFIG" log_sync_start_block_number "$ZGS_LOG_SYNC_BLOCK"
set_toml_string "$STAGED_CONFIG" blockchain_rpc_endpoint "$BLOCKCHAIN_RPC_ENDPOINT"

grep -Fqx 'rpc_enabled = true' "$STAGED_CONFIG" || { echo "Config validation failed: rpc_enabled." >&2; exit 1; }
grep -Fqx "rpc_listen_address = \"$RPC_LISTEN_ADDRESS\"" "$STAGED_CONFIG" || { echo "Config validation failed: rpc_listen_address." >&2; exit 1; }
grep -Fqx "blockchain_rpc_endpoint = \"$BLOCKCHAIN_RPC_ENDPOINT\"" "$STAGED_CONFIG" || { echo "Config validation failed: blockchain_rpc_endpoint." >&2; exit 1; }
grep -Fqx "log_sync_start_block_number = $ZGS_LOG_SYNC_BLOCK" "$STAGED_CONFIG" || { echo "Config validation failed: log_sync_start_block_number." >&2; exit 1; }
grep -Fqx "log_contract_address = \"$LOG_CONTRACT_ADDRESS\"" "$STAGED_CONFIG" || { echo "Config validation failed: log contract." >&2; exit 1; }
grep -Fqx "zgs_node_urls = \"$ZGS_NODE\"" "$STAGED_CONFIG" || { echo "Config validation failed: Storage node URLs." >&2; exit 1; }

echo
echo "Prepared Storage KV $TARGET_VERSION ($TARGET_COMMIT)."
echo "EVM chain ID: $EXPECTED_CHAIN_ID"
echo "Blockchain RPC: $BLOCKCHAIN_RPC_ENDPOINT"
echo "Storage nodes: $ZGS_NODE"
echo "KV RPC bind: $RPC_LISTEN_ADDRESS"
echo "No service or Storage KV checkout has been installed yet."
read -r -p "Type ACTIVATE-ZGSKV to install and start the service: " ACTIVATE_CONFIRM
[ "$ACTIVATE_CONFIRM" = "ACTIVATE-ZGSKV" ] || {
    echo "Activation cancelled. Staged files will be removed."
    exit 0
}

mkdir -p "$(dirname "$KV_DIR")"
mv "$STAGE_SRC" "$KV_DIR"

UNIT_TMP=$(mktemp)
cat > "$UNIT_TMP" <<EOF_UNIT
[Unit]
Description=0G Storage KV
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$KV_DIR/run
ExecStart=$KV_DIR/target/release/zgs_kv --config $KV_DIR/run/config.toml --log $KV_DIR/run/log_config
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=zgs_kv

[Install]
WantedBy=multi-user.target
EOF_UNIT
sudo install -m 0644 "$UNIT_TMP" "/etc/systemd/system/${SERVICE_NAME}.service"
rm -f "$UNIT_TMP"
sudo systemctl daemon-reload
if ! sudo systemctl enable --now "$SERVICE_NAME"; then
    sudo systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
    echo "Storage KV activation failed; service was left disabled. Inspect journalctl before retrying." >&2
    exit 1
fi
systemctl is-active --quiet "$SERVICE_NAME" || {
    sudo systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
    echo "Storage KV service did not remain active; it was disabled." >&2
    exit 1
}

echo "Storage KV $TARGET_VERSION installed from verified commit $TARGET_COMMIT."
echo "Service: ${SERVICE_NAME}.service"
echo "Logs: sudo journalctl -u $SERVICE_NAME -fn 100 -o cat"
echo "Upstream v1.5.1 remains review_required and was not installed by this workflow."
