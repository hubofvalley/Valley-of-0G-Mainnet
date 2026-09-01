#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RESET='\033[0m'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFEST_LIB="${VALLEY_MANIFEST_LIB:-$SCRIPT_DIR/valley_manifest.sh}"
[ -r "$MANIFEST_LIB" ] || { echo "Valley manifest loader not found: $MANIFEST_LIB" >&2; exit 2; }
# shellcheck source=resources/valley_manifest.sh
source "$MANIFEST_LIB"
valley_manifest_init

TARGET_VERSION=$(valley_manifest_get '.components.storage_node.version_current')
TARGET_TAG=$(valley_manifest_get '.components.storage_node.source_tag')
TARGET_COMMIT=$(valley_manifest_get '.components.storage_node.pinned_commit')
STORAGE_REPO=$(valley_manifest_get '.components.storage_node.release_repo')
EXPECTED_CHAIN_ID=$(valley_manifest_get '.chain.evm_chain_id')
valley_require_git_commit "$TARGET_COMMIT" || { echo "Invalid Storage commit in VERSIONS.json." >&2; exit 2; }

NODE_DIR="${ZGS_HOME:-$HOME/0g-storage-node}"
CONFIG_FILE="$NODE_DIR/run/config-mainnet.toml"
SERVICE_NAME="zgs"

rpc_result() {
    local endpoint=$1 method=$2
    curl -fsS --connect-timeout 4 --max-time 8 -X POST "$endpoint" \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":[],\"id\":1}" 2>/dev/null |
        jq -r '.result // empty' 2>/dev/null || true
}

hex_to_dec() {
    local value=$1
    if [[ "$value" =~ ^0x[0-9a-fA-F]+$ ]]; then printf '%d\n' "$((16#${value#0x}))";
    elif [[ "$value" =~ ^[0-9]+$ ]]; then printf '%s\n' "$value"; fi
}

require_rpc_chain() {
    local endpoint=$1 raw chain
    raw=$(rpc_result "$endpoint" eth_chainId)
    chain=$(hex_to_dec "$raw")
    [ "$chain" = "$EXPECTED_CHAIN_ID" ] || {
        echo "RPC rejected: $endpoint reports chain ${chain:-unavailable}; expected $EXPECTED_CHAIN_ID." >&2
        return 1
    }
    echo "RPC verified: chain=$chain"
}

choose_json_rpc_endpoint() {
    local choice public_choice continue_choice
    while true; do
        echo "Choose your JSON-RPC endpoint:"
        echo "1. Enter your own JSON-RPC endpoint"
        echo "2. Use a public JSON-RPC endpoint"
        read -r -p "Enter your choice (1/2): " choice
        case "$choice" in
            1)
                read -r -p "Enter your JSON-RPC endpoint: " BLOCKCHAIN_RPC_ENDPOINT
                if require_rpc_chain "$BLOCKCHAIN_RPC_ENDPOINT"; then
                    read -r -p "Do you want to continue with this RPC endpoint? (yes/no): " continue_choice
                    [ "$continue_choice" = "yes" ] && return 0
                fi
                ;;
            2)
                echo "Available public JSON-RPC endpoints:"
                echo "1. https://lightnode-json-rpc-mainnet-0g.grandvalleys.com"
                echo "2. https://evmrpc.0g.ai"
                read -r -p "Enter the number of your chosen public JSON-RPC endpoint: " public_choice
                case "$public_choice" in
                    1) BLOCKCHAIN_RPC_ENDPOINT="https://lightnode-json-rpc-mainnet-0g.grandvalleys.com" ;;
                    2) BLOCKCHAIN_RPC_ENDPOINT="https://evmrpc.0g.ai" ;;
                    *) echo "Invalid choice."; continue ;;
                esac
                require_rpc_chain "$BLOCKCHAIN_RPC_ENDPOINT" && return 0
                ;;
            *) echo "Invalid choice." ;;
        esac
    done
}

if [ -e "$NODE_DIR" ] || systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
    echo -e "${RED}Existing Storage node detected.${RESET}"
    echo "Safe-key mode will not delete or replace an existing mining instance. Use Update/Change instead."
    exit 1
fi

for tool in curl jq git systemctl; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required tool missing: $tool" >&2; exit 1; }
done

choose_json_rpc_endpoint

echo -e "${YELLOW}Storage mining-key boundary:${RESET}"
echo "Upstream ${TARGET_TAG} requires miner key material through its config or command-line interface."
echo "Valley will not collect that raw key or place it in argv, shell exports, or generated files."
echo "This installer will stage the reviewed binary, non-secret config, and service unit, but will NOT enable/start mining."
read -r -p "Type STAGE-STORAGE to continue: " confirm
[ "$confirm" = "STAGE-STORAGE" ] || { echo "Storage staging cancelled."; exit 0; }

sudo apt-get update -y
sudo apt-get install -y clang cmake build-essential git libssl-dev pkg-config protobuf-compiler llvm llvm-dev cargo

cd "$HOME"
git clone "$STORAGE_REPO.git" "$NODE_DIR"
cd "$NODE_DIR"
git fetch --tags --force
git checkout --detach "$TARGET_COMMIT"
[ "$(git rev-parse HEAD)" = "$TARGET_COMMIT" ] || { echo "Storage source pin verification failed." >&2; exit 1; }
git submodule update --init --recursive
cargo build --release

cp "$NODE_DIR/run/config-mainnet-turbo.toml" "$CONFIG_FILE"
sed -i -E \
    -e 's|^[[:space:]]*#?[[:space:]]*listen_address[[:space:]]*=.*|listen_address = "0.0.0.0:5678"|' \
    -e 's|^[[:space:]]*#?[[:space:]]*listen_address_admin[[:space:]]*=.*|listen_address_admin = "127.0.0.1:5679"|' \
    -e 's|^[[:space:]]*#?[[:space:]]*rpc_enabled[[:space:]]*=.*|rpc_enabled = true|' \
    -e 's|^[[:space:]]*#?[[:space:]]*log_sync_start_block_number[[:space:]]*=.*|log_sync_start_block_number = 2387557|' \
    -e "s|^[[:space:]]*#?[[:space:]]*blockchain_rpc_endpoint[[:space:]]*=.*|blockchain_rpc_endpoint = \"$BLOCKCHAIN_RPC_ENDPOINT\"|" \
    -e 's|^[[:space:]]*#?[[:space:]]*log_contract_address[[:space:]]*=.*|log_contract_address = "0x62D4144dB0F0a6fBBaeb6296c785C71B3D57C526"|' \
    -e 's|^[[:space:]]*#?[[:space:]]*mine_contract_address[[:space:]]*=.*|mine_contract_address = "0xCd01c5Cd953971CE4C2c9bFb95610236a7F414fe"|' \
    -e 's|^[[:space:]]*#?[[:space:]]*reward_contract_address[[:space:]]*=.*|reward_contract_address = "0x457aC76B58ffcDc118AABD6DbC63ff9072880870"|' \
    "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

if grep -Eq '^[[:space:]]*miner_key[[:space:]]*=[[:space:]]*"[^\"]+"' "$CONFIG_FILE"; then
    echo "Refusing to stage: source template unexpectedly contains populated miner_key." >&2
    exit 1
fi

sudo tee /etc/systemd/system/${SERVICE_NAME}.service >/dev/null <<EOF_UNIT
[Unit]
Description=0G Storage Node
After=network.target

[Service]
User=$USER
WorkingDirectory=$NODE_DIR/run
ExecStart=$NODE_DIR/target/release/zgs_node --config $CONFIG_FILE
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_UNIT
sudo systemctl daemon-reload

echo -e "${GREEN}Storage Node ${TARGET_VERSION} staged from immutable commit ${TARGET_COMMIT}.${RESET}"
echo "Service was NOT enabled or started because Valley does not handle the required raw miner key."
echo "Review the official upstream secret requirement and configure/start the service manually only if you accept that residual upstream limitation."
