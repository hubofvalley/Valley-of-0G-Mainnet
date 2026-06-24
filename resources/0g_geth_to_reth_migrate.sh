#!/bin/bash
set -euo pipefail

# ==== 0G Mainnet: Migrate from Geth to Reth ====
# This script migrates a running Geth-based validator/RPC node to Reth execution client.
# It preserves consensus data, exports Geth chain data, and imports into Reth.

GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RED="\e[31m"; ORANGE="\e[38;5;214m"; RESET="\e[0m"

echo -e "${ORANGE}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${ORANGE}║${RESET}  ${CYAN}0G Mainnet: Geth → Reth Migration${RESET}                       ${ORANGE}║${RESET}"
echo -e "${ORANGE}║${RESET}  ${YELLOW}This will replace your Geth execution client with Reth${RESET}  ${ORANGE}║${RESET}"
echo -e "${ORANGE}╚══════════════════════════════════════════════════════════╝${RESET}"

echo -e "\n${RED}▓▒░ IMPORTANT WARNINGS ░▒▓${RESET}"
echo -e "${YELLOW}1. Your Geth service will be stopped and disabled${RESET}"
echo -e "${YELLOW}2. Consensus data will be backed up automatically${RESET}"
echo -e "${YELLOW}3. Geth chain data will be exported and imported into Reth${RESET}"
echo -e "${YELLOW}4. This process may take hours depending on chain height and disk speed${RESET}"
echo -e "${YELLOW}5. Use tmux/screen session to prevent interruption${RESET}"

read -p $'\n\e[33mDo you want to proceed with migration? (yes/no): \e[0m' confirm
if [[ "${confirm,,}" != "yes" ]]; then
    echo -e "${RED}Migration cancelled.${RESET}"
    exit 0
fi

# Load env
source $HOME/.bash_profile 2>/dev/null || true

# Detect port prefix
if [ -z "${OG_PORT:-}" ]; then
    read -p "Enter your port prefix (e.g. 26): " OG_PORT
    OG_PORT=${OG_PORT:-26}
fi

# Detect service names
OG_SERVICE_NAME="${OG_SERVICE_NAME:-0gchaind}"
OG_GETH_SERVICE_NAME="${OG_GETH_SERVICE_NAME:-0g-geth}"

read -p "Enter Reth Service Name (default '0g-reth'): " OG_RETH_SERVICE_NAME
OG_RETH_SERVICE_NAME=${OG_RETH_SERVICE_NAME:-0g-reth}


# ETH RPC for validator restaking (optional, only if validator mode)
if [ "${NODE_TYPE:-}" = "validator" ] && [ -z "${ETH_RPC_URL:-}" ]; then
    read -p "Enter Mainnet ETH RPC endpoint (ETH_RPC_URL): " ETH_RPC_URL
    while [ -z "$ETH_RPC_URL" ]; do
        echo "ETH_RPC_URL cannot be empty for validator mode."
        read -p "Enter Mainnet ETH RPC endpoint (ETH_RPC_URL): " ETH_RPC_URL
    done
fi

echo -e "\n${CYAN}Migration Configuration:${RESET}"
echo -e "  Port Prefix:    ${OG_PORT}"
echo -e "  Consensus Svc:  ${OG_SERVICE_NAME}"
echo -e "  Geth Svc (old): ${OG_GETH_SERVICE_NAME}"
echo -e "  Reth Svc (new): ${OG_RETH_SERVICE_NAME}"
echo ""

# ==== STEP 1: Capture last block height from live Geth ====
echo -e "${CYAN}[Step 1/8] Capturing last block height from Geth...${RESET}"
CHAIN_HEAD=$(curl -s -X POST http://localhost:${OG_PORT}545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result' | xargs printf "%d\n" 2>/dev/null || echo "0")

if [ "$CHAIN_HEAD" = "0" ] || [ -z "$CHAIN_HEAD" ]; then
    echo -e "${YELLOW}Warning: Could not fetch block height from Geth RPC (port ${OG_PORT}545).${RESET}"
    read -p "Enter the last known block height manually: " CHAIN_HEAD
    while ! [[ "$CHAIN_HEAD" =~ ^[0-9]+$ ]]; do
        read -p "Please enter a valid block number: " CHAIN_HEAD
    done
fi
echo -e "${GREEN}Last block height: $CHAIN_HEAD${RESET}"

# ==== STEP 2: Stop services & backup ====
echo -e "${CYAN}[Step 2/8] Stopping services and creating backup...${RESET}"
sudo systemctl stop ${OG_SERVICE_NAME} 2>/dev/null || true
sudo systemctl stop ${OG_GETH_SERVICE_NAME} 2>/dev/null || true

# Backup consensus data
BACKUP_DIR="$HOME/.0gchaind/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
cp -r $HOME/.0gchaind/0g-home/0gchaind-home $BACKUP_DIR/0gchaind-home
echo -e "${GREEN}Consensus data backed up to: $BACKUP_DIR${RESET}"

# ==== STEP 3: Download Aristotle v1.0.6 & copy binaries ====
echo -e "${CYAN}[Step 3/8] Downloading Aristotle v1.0.6 and preparing Reth binary...${RESET}"
cd $HOME
if [ ! -f "$HOME/aristotle/bin/reth" ] && [ ! -f "$HOME/go/bin/0g-reth" ]; then
    wget -q -O aristotle.tar.gz https://github.com/0gfoundation/0gchain-Aristotle/releases/download/v1.0.6/aristotle-v1.0.6.tar.gz
    rm -rf aristotle-used
    tar -xzvf aristotle.tar.gz -C $HOME
    # Handle both possible extracted dir names
    if [ -d "Aristotle-v1.0.6" ]; then
        mv Aristotle-v1.0.6 aristotle-used
    elif [ -d "aristotle-v1.0.6" ]; then
        mv aristotle-v1.0.6 aristotle-used
    elif [ ! -d "aristotle-used" ]; then
        echo -e "${RED}Error: Could not find extracted directory.${RESET}"
        exit 1
    fi
    rm -f aristotle.tar.gz
else
    # Use existing aristotle directory
    if [ -d "$HOME/aristotle" ] && [ ! -d "$HOME/aristotle-used" ]; then
        cp -r $HOME/aristotle $HOME/aristotle-used
    fi
fi

# Copy binaries
sudo chmod +x $HOME/aristotle-used/bin/reth $HOME/aristotle-used/bin/0gchaind 2>/dev/null || true
cp $HOME/aristotle-used/bin/reth $HOME/go/bin/0g-reth
cp $HOME/aristotle-used/bin/0gchaind $HOME/go/bin/0gchaind

# Reth data dir
mkdir -p $HOME/.0gchaind/0g-home/reth-home

# Copy JWT and KZG files
cp -f $HOME/aristotle-used/jwt.hex $HOME/.0gchaind/0g-home/ 2>/dev/null || true
cp -f $HOME/aristotle-used/kzg-trusted-setup.json $HOME/.0gchaind/0g-home/ 2>/dev/null || true
echo -e "${GREEN}Reth binary and config files ready.${RESET}"

# ==== STEP 4: Export Geth data to RLP ====
echo -e "${CYAN}[Step 4/8] Exporting Geth chain data to RLP...${RESET}"
echo -e "${YELLOW}This may take a long time depending on chain height and disk speed.${RESET}"
echo -e "${YELLOW}Chain will be exported from block 1 to block $CHAIN_HEAD${RESET}"

# Check if geth binary exists
GETH_BIN=""
if [ -x "$HOME/go/bin/0g-geth" ]; then
    GETH_BIN="$HOME/go/bin/0g-geth"
elif [ -x "$HOME/go/bin/geth" ]; then
    GETH_BIN="$HOME/go/bin/geth"
elif [ -x "$HOME/aristotle/bin/geth" ]; then
    GETH_BIN="$HOME/aristotle/bin/geth"
elif [ -x "$HOME/aristotle-used/bin/geth" ]; then
    GETH_BIN="$HOME/aristotle-used/bin/geth"
else
    echo -e "${RED}Error: Cannot find geth binary for export. Please provide path:${RESET}"
    read -p "Geth binary path: " GETH_BIN
    if [ ! -x "$GETH_BIN" ]; then
        echo -e "${RED}Invalid binary path. Aborting.${RESET}"
        exit 1
    fi
fi

$GETH_BIN export \
  --datadir $HOME/.0gchaind/0g-home/geth-home \
  $HOME/.0gchaind/0g-home/chain-export.rlp \
  1 $CHAIN_HEAD

echo -e "${GREEN}Geth data exported successfully.${RESET}"

# ==== STEP 5: Init Reth and trim RLP ====
echo -e "${CYAN}[Step 5/8] Initializing Reth and trimming genesis block from RLP...${RESET}"

# Init reth
GENESIS_JSON="$HOME/aristotle-used/geth-genesis.json"
if [ ! -f "$GENESIS_JSON" ]; then
    GENESIS_JSON="$HOME/.0gchaind/geth-genesis.json"
fi
if [ ! -f "$GENESIS_JSON" ]; then
    echo -e "${RED}Error: Genesis file not found at $GENESIS_JSON${RESET}"
    echo -e "${YELLOW}Ensure aristotle package is properly extracted.${RESET}"
    exit 1
fi
$HOME/go/bin/0g-reth init \
  --chain $GENESIS_JSON \
  --datadir $HOME/.0gchaind/0g-home/reth-home

# Create trim script
cat > $HOME/.0gchaind/0g-home/trim_export.py <<'PYEOF'
import sys

input_file = sys.argv[1] if len(sys.argv) > 1 else "chain-export.rlp"
start_block = int(sys.argv[2]) if len(sys.argv) > 2 else 1
output_file = input_file.rsplit('.', 1)[0] + f"-from-{start_block}.rlp"

print(f"Trimming blocks before {start_block}, output: {output_file}")

def read_rlp_length(f):
    first = f.read(1)
    if not first:
        return None, 0
    b = first[0]
    if b < 0xc0:
        return None, 0
    elif b <= 0xf7:
        return first, b - 0xc0
    else:
        len_bytes_count = b - 0xf7
        len_bytes = f.read(len_bytes_count)
        return first + len_bytes, int.from_bytes(len_bytes, 'big')

def get_block_number(block_data):
    offset = 0
    b = block_data[offset]
    offset += 1 if b <= 0xf7 else 1 + (b - 0xf7)
    b = block_data[offset]
    offset += 1 if b <= 0xf7 else 1 + (b - 0xf7)
    for _ in range(8):
        b = block_data[offset]
        if b <= 0x80:
            offset += 1
        elif b <= 0xb7:
            offset += 1 + (b - 0x80)
        elif b <= 0xbf:
            n = b - 0xb7
            offset += 1 + n + int.from_bytes(block_data[offset+1:offset+1+n], 'big')
        elif b <= 0xf7:
            offset += 1 + (b - 0xc0)
        else:
            n = b - 0xf7
            offset += 1 + n + int.from_bytes(block_data[offset+1:offset+1+n], 'big')
    b = block_data[offset]
    if b == 0x80: return 0
    if b < 0x80: return b
    length = b - 0x80
    return int.from_bytes(block_data[offset+1:offset+1+length], 'big')

block_count = 0
skipped = 0

with open(input_file, "rb") as fin, open(output_file, "wb") as fout:
    while True:
        header_bytes, length = read_rlp_length(fin)
        if header_bytes is None:
            break
        block_body = fin.read(length)
        if len(block_body) < length:
            break
        full_block = header_bytes + block_body
        try:
            block_number = get_block_number(full_block)
        except Exception as e:
            print(f"Warning: could not parse block at index {block_count + skipped}, writing anyway: {e}")
            fout.write(full_block)
            block_count += 1
            continue
        if block_number < start_block:
            skipped += 1
            if skipped % 100000 == 0:
                print(f"Skipped {skipped} blocks (current: {block_number})...")
        else:
            fout.write(full_block)
            block_count += 1
            if block_count % 100000 == 0:
                print(f"Written {block_count} blocks (current: {block_number})...")

print(f"Done. Skipped {skipped}, wrote {block_count} blocks to {output_file}")
PYEOF

# Run trim
python3 $HOME/.0gchaind/0g-home/trim_export.py $HOME/.0gchaind/0g-home/chain-export.rlp 1
echo -e "${GREEN}Genesis block trimmed from RLP export.${RESET}"

# ==== STEP 6: Import RLP into Reth ====
echo -e "${CYAN}[Step 6/8] Importing chain data into Reth...${RESET}"
echo -e "${YELLOW}This is the longest step. Importing blocks into Reth database...${RESET}"
echo -e "${RED}DO NOT interrupt this process!${RESET}"

TRIMMED_RLP="$HOME/.0gchaind/0g-home/chain-export-from-1.rlp"
IMPORT_LOG="$HOME/.0gchaind/0g-home/reth-import.log"

set +e
$HOME/go/bin/0g-reth import \
  --chain $GENESIS_JSON \
  --datadir $HOME/.0gchaind/0g-home/reth-home \
  $TRIMMED_RLP 2>&1 | tee $IMPORT_LOG
IMPORT_EXIT=${PIPESTATUS[0]}
set -e
if [ $IMPORT_EXIT -ne 0 ]; then
    echo -e "${RED}Reth import failed! Check log: $IMPORT_LOG${RESET}"
    echo -e "${YELLOW}If error is 'block number X does not match parent block number Y':${RESET}"
    echo -e "  1. Re-trim from Y+1:"
    echo -e "     python3 \$HOME/.0gchaind/0g-home/trim_export.py \$HOME/.0gchaind/0g-home/chain-export.rlp <Y+1>"
    echo -e "  2. Re-import the trimmed file:"
    echo -e "     \$HOME/go/bin/0g-reth import --chain $GENESIS_JSON --datadir \$HOME/.0gchaind/0g-home/reth-home \$HOME/.0gchaind/0g-home/chain-export-from-<Y+1>.rlp"
    echo -e "${YELLOW}Otherwise retry full import:${RESET}"
    echo -e "  \$HOME/go/bin/0g-reth import --chain $GENESIS_JSON --datadir \$HOME/.0gchaind/0g-home/reth-home $TRIMMED_RLP"
    exit 1
fi

echo -e "${GREEN}Reth import completed successfully!${RESET}"

# ==== STEP 7: Update config & create service files ====
echo -e "${CYAN}[Step 7/8] Updating configuration and creating service files...${RESET}"

EXTERNAL_IP=$(curl -4 -s ifconfig.me)

# Update app.toml engine connection
sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" \
  $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml

# Disable old Geth service
sudo systemctl disable ${OG_GETH_SERVICE_NAME} 2>/dev/null || true
sudo rm -f /etc/systemd/system/${OG_GETH_SERVICE_NAME}.service 2>/dev/null || true

# Create Reth service
sudo tee /etc/systemd/system/${OG_RETH_SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=0G Reth Execution Client - ${OG_RETH_SERVICE_NAME}
After=network-online.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0g-reth node \\
  --chain $GENESIS_JSON \\
  --http \\
  --http.addr 0.0.0.0 \\
  --http.port ${OG_PORT}545 \\
  --http.api eth,net,admin \\
  --authrpc.addr 0.0.0.0 \\
  --authrpc.port ${OG_PORT}551 \\
  --authrpc.jwtsecret $HOME/.0gchaind/0g-home/jwt.hex \\
  --datadir $HOME/.0gchaind/0g-home/reth-home \\
  --ipcpath $HOME/.0gchaind/0g-home/reth-home/eth-engine.ipc \\
  --engine.persistence-threshold 0 \\
  --engine.memory-block-buffer-target 0 \\
  --bootnodes="enode://2bf74c837a98c94ad0fa8f5c58a428237d2040f9269fe622c3dbe4fef68141c28e2097d7af6ebaa041194257543dc112514238361a6498f9a38f70fd56493f96@8.221.140.134:30303" \\
  --port ${OG_PORT}303 \\
  --nat extip:${EXTERNAL_IP}
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Update consensus service file
if [ "${NODE_TYPE:-}" = "validator" ] && [ -n "${ETH_RPC_URL:-}" ]; then
sudo tee /etc/systemd/system/${OG_SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=0gchaind Node Service - ${OG_SERVICE_NAME} (Validator + Reth)
After=network-online.target

[Service]
User=$USER
Environment=CHAIN_SPEC=mainnet
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0gchaind start \\
  --rpc.laddr tcp://0.0.0.0:${OG_PORT}657 \\
  --chaincfg.chain-spec mainnet \\
  --chaincfg.restaking.enabled \\
  --chaincfg.restaking.symbiotic-rpc-dial-url ${ETH_RPC_URL} \\
  --chaincfg.restaking.symbiotic-get-logs-block-range ${BLOCK_NUM:-1} \\
  --home $HOME/.0gchaind/0g-home/0gchaind-home \\
  --chaincfg.kzg.trusted-setup-path=$HOME/.0gchaind/0g-home/kzg-trusted-setup.json \\
  --chaincfg.engine.jwt-secret-path=$HOME/.0gchaind/0g-home/jwt.hex \\
  --chaincfg.block-store-service.enabled \\
  --chaincfg.node-api.enabled \\
  --chaincfg.node-api.address 0.0.0.0:${OG_PORT}500 \\
  --chaincfg.engine.rpc-dial-url=http://localhost:${OG_PORT}551 \\
  --pruning=nothing \\
  --p2p.external_address=${EXTERNAL_IP}:${OG_PORT}656
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
else
sudo tee /etc/systemd/system/${OG_SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=0gchaind Node Service - ${OG_SERVICE_NAME} (RPC + Reth)
After=network-online.target

[Service]
User=$USER
Environment=CHAIN_SPEC=mainnet
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0gchaind start \\
  --rpc.laddr tcp://0.0.0.0:${OG_PORT}657 \\
  --chaincfg.chain-spec mainnet \\
  --home $HOME/.0gchaind/0g-home/0gchaind-home \\
  --chaincfg.kzg.trusted-setup-path=$HOME/.0gchaind/0g-home/kzg-trusted-setup.json \\
  --chaincfg.engine.jwt-secret-path=$HOME/.0gchaind/0g-home/jwt.hex \\
  --chaincfg.block-store-service.enabled \\
  --chaincfg.node-api.enabled \\
  --chaincfg.node-api.address 0.0.0.0:${OG_PORT}500 \\
  --chaincfg.engine.rpc-dial-url=http://localhost:${OG_PORT}551 \\
  --pruning=nothing \\
  --p2p.external_address=${EXTERNAL_IP}:${OG_PORT}656
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
fi

# ==== STEP 8: Start services ====
echo -e "${CYAN}[Step 8/8] Starting Reth and consensus services...${RESET}"
sudo systemctl daemon-reload
sudo systemctl enable ${OG_RETH_SERVICE_NAME} ${OG_SERVICE_NAME}

# Start Reth FIRST
sudo systemctl start ${OG_RETH_SERVICE_NAME}

# Wait for Engine API port
echo -e "${YELLOW}Waiting for Reth Engine API port (${OG_PORT}551)...${RESET}"
for i in $(seq 1 30); do
  if ss -tlnp | grep -q "${OG_PORT}551"; then
    echo -e "${GREEN}Reth Engine API is ready.${RESET}"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo -e "${YELLOW}Warning: Engine API not detected after 30s. Starting consensus anyway...${RESET}"
  fi
  sleep 1
done

# Start consensus
sudo systemctl start ${OG_SERVICE_NAME}

# Update env vars
sed -i '/OG_GETH_SERVICE_NAME/d' $HOME/.bash_profile 2>/dev/null || true
sed -i '/EXEC_CLIENT/d' $HOME/.bash_profile 2>/dev/null || true
{
  echo "export EXEC_CLIENT=\"reth\""
  echo "export OG_RETH_SERVICE_NAME=\"$OG_RETH_SERVICE_NAME\""
} >> $HOME/.bash_profile

echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║  Migration from Geth to Reth completed successfully!    ║${RESET}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo -e "\n${YELLOW}Service Status:${RESET}"
echo -e "  Reth service:      ${OG_RETH_SERVICE_NAME} (${GREEN}enabled${RESET})"
echo -e "  Consensus service: ${OG_SERVICE_NAME} (${GREEN}enabled${RESET})"
echo -e "  Old Geth service:  ${OG_GETH_SERVICE_NAME} (${RED}disabled${RESET})"
echo -e "\n${YELLOW}Backup location:${RESET} $BACKUP_DIR"
echo -e "\n${YELLOW}Monitor logs:${RESET}"
echo -e "  Reth:      sudo journalctl -u ${OG_RETH_SERVICE_NAME} -f -o cat"
echo -e "  Consensus: sudo journalctl -u ${OG_SERVICE_NAME} -f -o cat"
echo -e "\n${YELLOW}Cleanup (after verifying everything works):${RESET}"
echo -e "  rm -rf $HOME/.0gchaind/0g-home/chain-export*.rlp"
echo -e "  rm -f $HOME/.0gchaind/0g-home/trim_export.py"

echo -e "\n${YELLOW}Press Enter to return to menu...${RESET}"
read -r

