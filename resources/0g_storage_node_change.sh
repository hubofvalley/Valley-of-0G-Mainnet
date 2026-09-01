#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${ZGS_CONFIG_FILE:-$HOME/0g-storage-node/run/config-mainnet.toml}"
SERVICE_NAME="zgs"
EXPECTED_CHAIN_ID="16661"

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
    local endpoint=$1 chain
    chain=$(hex_to_dec "$(rpc_result "$endpoint" eth_chainId)")
    [ "$chain" = "$EXPECTED_CHAIN_ID" ] || { echo "RPC rejected: expected chain $EXPECTED_CHAIN_ID, got ${chain:-unavailable}." >&2; return 1; }
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
                require_rpc_chain "$BLOCKCHAIN_RPC_ENDPOINT" || continue
                read -r -p "Do you want to continue with this RPC endpoint? (yes/no): " continue_choice
                [ "$continue_choice" = "yes" ] && return 0
                ;;
            2)
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

[ -f "$CONFIG_FILE" ] || { echo "Storage config not found: $CONFIG_FILE" >&2; exit 1; }
echo "Choose what you want to change:"
echo "1. Change RPC endpoint"
echo "2. Change miner key"
read -r -p "Enter your choice (1/2): " USER_CHOICE
case "$USER_CHOICE" in
    1) choose_json_rpc_endpoint ;;
    2)
        echo "Miner-key changes are intentionally not automated."
        echo "Upstream Storage requires raw key material in config/argv; Valley will not collect or rewrite it."
        echo "Review the official upstream procedure and make the operator-owned change manually if you accept that limitation."
        exit 0
        ;;
    *) echo "Invalid choice. Exiting." >&2; exit 1 ;;
esac

backup="${CONFIG_FILE}.valley-backup.$(date -u +%Y%m%dT%H%M%SZ)"
cp "$CONFIG_FILE" "$backup"
chmod 600 "$backup"
candidate=$(mktemp)
trap 'rm -f "$candidate"' EXIT
cp "$CONFIG_FILE" "$candidate"
chmod 600 "$candidate"
sed -i -E "s|^[[:space:]]*blockchain_rpc_endpoint[[:space:]]*=.*|blockchain_rpc_endpoint = \"$BLOCKCHAIN_RPC_ENDPOINT\"|" "$candidate"
grep -Fq "blockchain_rpc_endpoint = \"$BLOCKCHAIN_RPC_ENDPOINT\"" "$candidate" || { echo "Candidate validation failed." >&2; exit 1; }

sudo systemctl stop "$SERVICE_NAME"
install -m 0600 "$candidate" "$CONFIG_FILE"
if ! sudo systemctl restart "$SERVICE_NAME" || ! systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "Storage service failed after RPC change; restoring previous config." >&2
    cp "$backup" "$CONFIG_FILE"
    sudo systemctl restart "$SERVICE_NAME" || true
    exit 1
fi
echo "Storage RPC endpoint updated. Existing miner key value was not read or rewritten."
echo "Backup retained at: $backup"
