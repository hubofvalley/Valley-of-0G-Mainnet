#!/bin/bash

# ==== CONFIG ====
echo -e "\n--- 0G Mainnet Node Setup (Validator or RPC) ---"

LOGO="
 __                                   
/__ ._ _. ._   _|   \  / _. | |  _    
\_| | (_| | | (_|    \/ (_| | | (/_ \/
                                    /
"
echo "$LOGO"

# Colours
GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RESET="\e[0m"

# ===== CHOOSE NODE TYPE =====
while true; do
  read -p "Deploy type? (validator/rpc): " NODE_TYPE
  NODE_TYPE=$(echo "$NODE_TYPE" | tr '[:upper:]' '[:lower:]')
  if [[ "$NODE_TYPE" == "validator" || "$NODE_TYPE" == "rpc" ]]; then
    break
  else
    echo "Please type exactly 'validator' or 'rpc'."
  fi
done

# ===== CHOOSE EXECUTION CLIENT =====
echo -e "\n${CYAN}Select Execution Client:${RESET}"
echo -e "  ${GREEN}1) Geth${RESET}  - Original 0G execution client (stable, battle-tested)"
echo -e "  ${GREEN}2) Reth${RESET}  - High-performance Rust execution client (faster sync, lower resource usage)"
while true; do
  read -p "Enter your choice (1 or 2): " EL_CHOICE
  case "$EL_CHOICE" in
    1) EXEC_CLIENT="geth"; break ;;
    2) EXEC_CLIENT="reth"; break ;;
    *) echo "Please enter 1 or 2." ;;
  esac
done
echo -e "Selected execution client: ${CYAN}${EXEC_CLIENT}${RESET}"

# Prompt for OG_MONIKER, OG_PORT, Indexer
read -p "Enter your moniker: " OG_MONIKER
read -p "Enter your preferred port number: (leave empty to use default: 26) " OG_PORT
if [ -z "$OG_PORT" ]; then
    OG_PORT=26
fi
read -p "Do you want to enable the indexer? (yes/no): " ENABLE_INDEXER
read -p "Configure UFW firewall rules for 0G? (y/n): " SETUP_UFW

# Extra prompts for VALIDATOR
if [ "$NODE_TYPE" = "validator" ]; then
  read -p "Enter Mainnet ETH RPC endpoint (ETH_RPC_URL): " ETH_RPC_URL
  while [ -z "$ETH_RPC_URL" ]; do
    echo "ETH_RPC_URL cannot be empty for validator mode."
    read -p "Enter Mainnet ETH RPC endpoint (ETH_RPC_URL): " ETH_RPC_URL
  done
  read -p "Enter block range to fetch logs (BLOCK_NUM), e.g. 2000: " BLOCK_NUM
  while ! [[ "$BLOCK_NUM" =~ ^[0-9]+$ ]]; do
    echo "BLOCK_NUM must be a positive integer."
    read -p "Enter block range to fetch logs (BLOCK_NUM), e.g. 2000: " BLOCK_NUM
  done
fi

# Service Name Configuration (for multi-instance support)
if [ -z "$OG_SERVICE_NAME" ]; then
    read -p "Enter Consensus Service Name (default '0gchaind'): " OG_SERVICE_NAME
    OG_SERVICE_NAME=${OG_SERVICE_NAME:-0gchaind}
fi

if [ "$EXEC_CLIENT" = "geth" ]; then
    if [ -z "$OG_GETH_SERVICE_NAME" ]; then
        read -p "Enter Geth Service Name (default '0g-geth'): " OG_GETH_SERVICE_NAME
        OG_GETH_SERVICE_NAME=${OG_GETH_SERVICE_NAME:-0g-geth}
    fi
    echo "Using Service Names: ${OG_SERVICE_NAME} and ${OG_GETH_SERVICE_NAME}"
else
    read -p "Enter Reth Service Name (default '0g-reth'): " OG_RETH_SERVICE_NAME
    OG_RETH_SERVICE_NAME=${OG_RETH_SERVICE_NAME:-0g-reth}

    echo "Using Service Names: ${OG_SERVICE_NAME} and ${OG_RETH_SERVICE_NAME}"
fi

# Save env vars
{
  echo "export OG_MONIKER=\"$OG_MONIKER\""
  echo "export OG_PORT=\"$OG_PORT\""
  echo "export NODE_TYPE=\"$NODE_TYPE\""
  echo "export EXEC_CLIENT=\"$EXEC_CLIENT\""
  echo "export OG_SERVICE_NAME=\"$OG_SERVICE_NAME\""
  if [ "$EXEC_CLIENT" = "geth" ]; then
    echo "export OG_GETH_SERVICE_NAME=\"$OG_GETH_SERVICE_NAME\""
  else
    echo "export OG_RETH_SERVICE_NAME=\"$OG_RETH_SERVICE_NAME\""
  fi
  if [ "$NODE_TYPE" = "validator" ]; then
    echo "export ETH_RPC_URL=\"$ETH_RPC_URL\""
    echo "export BLOCK_NUM=\"$BLOCK_NUM\""
  fi
  echo 'export PATH=$PATH:$HOME/aristotle/bin'
  } >> ~/.bash_profile
  source ~/.bash_profile

# ==== CLEANUP EXISTING INSTALLATION ====
echo -e "\n?? Cleaning up any existing 0G node installation..."

# Stop and disable services (uses both hardcoded and custom names for compatibility)
sudo systemctl stop 0gchaind ${OG_SERVICE_NAME} 2>/dev/null || true
sudo systemctl stop 0g-geth 0ggeth reth 0g-reth ${OG_GETH_SERVICE_NAME:-_skip_} ${OG_RETH_SERVICE_NAME:-_skip_} 2>/dev/null || true
sudo systemctl disable 0gchaind ${OG_SERVICE_NAME} 2>/dev/null || true
sudo systemctl disable 0g-geth 0ggeth reth 0g-reth ${OG_GETH_SERVICE_NAME:-_skip_} ${OG_RETH_SERVICE_NAME:-_skip_} 2>/dev/null || true
sudo rm -f /etc/systemd/system/0gchaind.service /etc/systemd/system/0g-geth.service /etc/systemd/system/0ggeth.service /etc/systemd/system/reth.service /etc/systemd/system/0g-reth.service
sudo rm -f /etc/systemd/system/${OG_SERVICE_NAME}.service /etc/systemd/system/${OG_GETH_SERVICE_NAME:-_skip_}.service /etc/systemd/system/${OG_RETH_SERVICE_NAME:-_skip_}.service 2>/dev/null || true
sudo rm -f $HOME/go/bin/0gchaind $HOME/go/bin/0g-geth $HOME/go/bin/0ggeth $HOME/go/bin/reth $HOME/go/bin/0g-reth
rm -rf $HOME/.0gchaind $HOME/aristotle $HOME/aristotle-v1.0.4 $HOME/aristotle-v1.0.4.tar.gz $HOME/aristotle-v1.0.6 $HOME/aristotle-v1.0.6.tar.gz

echo "? Cleanup complete."

# ==== DEPENDENCIES ====
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git wget htop tmux build-essential jq make lz4 gcc unzip

# ==== INSTALL GO ====
cd $HOME && ver="1.22.5"
wget -q "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
rm "go$ver.linux-amd64.tar.gz"
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bash_profile
source ~/.bash_profile
[ ! -d ~/go/bin ] && mkdir -p ~/go/bin
go version

# Optional: Configure UFW based on chosen ports
if [[ "$SETUP_UFW" =~ ^[Yy]$ ]]; then
    sudo apt install -y ufw
    sudo ufw allow 22/tcp comment "SSH Access"
    sudo ufw allow ${OG_PORT}303/tcp comment "0g-geth Mainnet P2P"
    sudo ufw allow ${OG_PORT}303/udp comment "0g-geth Mainnet discovery"
    sudo ufw allow ${OG_PORT}656/tcp comment "0g Mainnet CometBFT P2P"
    sudo ufw --force enable
    sudo ufw status verbose
fi

# ==== DOWNLOAD ARISTOTLE v1.0.6 ====
cd $HOME
sudo rm -rf aristotle
wget -q https://github.com/0gfoundation/0gchain-Aristotle/releases/download/v1.0.6/aristotle-v1.0.6.tar.gz -O aristotle-v1.0.6.tar.gz
tar -xzvf aristotle-v1.0.6.tar.gz
mv aristotle-v1.0.6 aristotle
sudo rm aristotle-v1.0.6.tar.gz

# ==== MAKE BINARIES EXECUTABLE ====
sudo chmod +x $HOME/aristotle/bin/geth $HOME/aristotle/bin/reth $HOME/aristotle/bin/0gchaind 2>/dev/null || true

# ==== MOVE BINARIES ====
if [ "$EXEC_CLIENT" = "geth" ]; then
    cp $HOME/aristotle/bin/geth $HOME/go/bin/0g-geth
else
    cp $HOME/aristotle/bin/reth $HOME/go/bin/0g-reth
fi
cp $HOME/aristotle/bin/0gchaind $HOME/go/bin/0gchaind

# ==== INIT CHAIN ====
mkdir -p $HOME/.0gchaind/
cp -r $HOME/aristotle/* $HOME/.0gchaind/
if [ "$EXEC_CLIENT" = "geth" ]; then
    0g-geth init --datadir $HOME/.0gchaind/0g-home/geth-home $HOME/.0gchaind/geth-genesis.json
else
    0g-reth init --chain $HOME/.0gchaind/geth-genesis.json --datadir $HOME/.0gchaind/0g-home/reth-home
fi
0gchaind init "$OG_MONIKER" --home $HOME/.0gchaind/tmp --chaincfg.chain-spec mainnet

# ==== COPY KEYS ====
cp $HOME/.0gchaind/tmp/data/priv_validator_state.json $HOME/.0gchaind/0g-home/0gchaind-home/data/
cp $HOME/.0gchaind/tmp/config/node_key.json $HOME/.0gchaind/0g-home/0gchaind-home/config/
cp $HOME/.0gchaind/tmp/config/priv_validator_key.json $HOME/.0gchaind/0g-home/0gchaind-home/config/

# ==== Generate JWT Authentication Token ====
0gchaind jwt generate --home $HOME/.0gchaind/0g-home/0gchaind-home --chaincfg.chain-spec mainnet
cp -f $HOME/.0gchaind/0g-home/0gchaind-home/config/jwt.hex $HOME/.0gchaind/jwt.hex

# ==== CONFIG PATCH ====
CONFIG="$HOME/.0gchaind/0g-home/0gchaind-home/config"
GCONFIG="$HOME/.0gchaind/geth-config.toml"
EXTERNAL_IP=$(curl -4 -s ifconfig.me)

# config.toml
sed -i "s/^moniker *=.*/moniker = \"$OG_MONIKER\"/" $CONFIG/config.toml
sed -i "s|laddr = \"tcp://0.0.0.0:26656\"|laddr = \"tcp://0.0.0.0:${OG_PORT}656\"|" $CONFIG/config.toml
sed -i "s|laddr = \"tcp://127.0.0.1:26657\"|laddr = \"tcp://127.0.0.1:${OG_PORT}657\"|" $CONFIG/config.toml
sed -i "s|^proxy_app = .*|proxy_app = \"tcp://127.0.0.1:${OG_PORT}658\"|" $CONFIG/config.toml
sed -i "s|^pprof_laddr = .*|pprof_laddr = \"0.0.0.0:${OG_PORT}060\"|" $CONFIG/config.toml
sed -i "s|prometheus_listen_addr = \".*\"|prometheus_listen_addr = \"0.0.0.0:${OG_PORT}660\"|" $CONFIG/config.toml
sed -i "s/^timeout_commit *=.*/timeout_commit = \"200ms\"/" $CONFIG/config.toml

# indexer toggle
if [ "$ENABLE_INDEXER" = "yes" ]; then
  sed -i -e 's/^indexer = "null"/indexer = "kv"/' $CONFIG/config.toml
  echo "Indexer enabled."
else
  sed -i -e 's/^indexer = "kv"/indexer = "null"/' $CONFIG/config.toml
  echo "Indexer disabled."
fi

# app.toml
sed -i "s|address = \".*:3500\"|address = \"127.0.0.1:${OG_PORT}500\"|" $CONFIG/app.toml
sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" $CONFIG/app.toml
sed -i "s/^pruning *=.*/pruning = \"custom\"/" $CONFIG/app.toml
sed -i "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/" $CONFIG/app.toml
sed -i "s/^pruning-interval *=.*/pruning-interval = \"19\"/" $CONFIG/app.toml
sed -i "s/^payload-timeout *=.*/payload-timeout = \"200ms\"/" $CONFIG/app.toml

if [ "$EXEC_CLIENT" = "geth" ]; then
    # geth-config.toml
    sed -i "s/HTTPPort = .*/HTTPPort = ${OG_PORT}545/" $GCONFIG
    sed -i "s/WSPort = .*/WSPort = ${OG_PORT}546/" $GCONFIG
    sed -i "s/AuthPort = .*/AuthPort = ${OG_PORT}551/" $GCONFIG
    sed -i "s/ListenAddr = .*/ListenAddr = \":${OG_PORT}303\"/" $GCONFIG
    sed -i "s/DiscAddr = .*/DiscAddr = \":${OG_PORT}303\"/" $GCONFIG
    sed -i "s/^# *Port = .*/# Port = ${OG_PORT}901/" $GCONFIG
    sed -i "s/^# *InfluxDBEndpoint = .*/# InfluxDBEndpoint = \"http:\/\/localhost:${OG_PORT}086\"/" $GCONFIG
else
    # Reth client.toml symlink for 0gchaind
    mkdir -p $HOME/.0gchaind/config
    ln -sf $HOME/.0gchaind/0g-home/0gchaind-home/config/client.toml $HOME/.0gchaind/config/client.toml
fi

# ==== SYSTEMD SERVICES ====
if [ "$EXEC_CLIENT" = "reth" ]; then
    EXTRA_CL_FLAGS="--chaincfg.block-store-service.enabled \\\\
  --chaincfg.node-api.enabled \\\\
  --chaincfg.node-api.address 0.0.0.0:${OG_PORT}500 \\\\
  --pruning=nothing"
else
    EXTRA_CL_FLAGS=""
fi

# Consensus service file (branch on NODE_TYPE)
if [ "$NODE_TYPE" = "validator" ]; then
sudo tee /etc/systemd/system/${OG_SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=0gchaind Node Service - ${OG_SERVICE_NAME} (Validator + ${EXEC_CLIENT})
After=network-online.target

[Service]
User=$USER
Environment=CHAIN_SPEC=mainnet
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0gchaind start \\
  --chaincfg.chain-spec mainnet \\
  --chaincfg.restaking.enabled \\
  --chaincfg.restaking.symbiotic-rpc-dial-url ${ETH_RPC_URL} \\
  --chaincfg.restaking.symbiotic-get-logs-block-range ${BLOCK_NUM} \\
  --home $HOME/.0gchaind/0g-home/0gchaind-home \\
  --chaincfg.kzg.trusted-setup-path=$HOME/.0gchaind/kzg-trusted-setup.json \\
  --chaincfg.engine.jwt-secret-path=$HOME/.0gchaind/jwt.hex \\
  --chaincfg.kzg.implementation=crate-crypto/go-kzg-4844 \\
  --chaincfg.engine.rpc-dial-url=http://localhost:${OG_PORT}551 \\
  ${EXTRA_CL_FLAGS:-} \\
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
Description=0gchaind Node Service - ${OG_SERVICE_NAME} (RPC + ${EXEC_CLIENT})
After=network-online.target

[Service]
User=$USER
Environment=CHAIN_SPEC=mainnet
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0gchaind start \\
  --chaincfg.chain-spec mainnet \\
  --home $HOME/.0gchaind/0g-home/0gchaind-home \\
  --chaincfg.kzg.trusted-setup-path=$HOME/.0gchaind/kzg-trusted-setup.json \\
  --chaincfg.engine.jwt-secret-path=$HOME/.0gchaind/jwt.hex \\
  --chaincfg.kzg.implementation=crate-crypto/go-kzg-4844 \\
  --chaincfg.engine.rpc-dial-url=http://localhost:${OG_PORT}551 \\
  ${EXTRA_CL_FLAGS:-} \\
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

# ---- Execution Layer Service ----
if [ "$EXEC_CLIENT" = "geth" ]; then
    # Geth service file
    sudo tee /etc/systemd/system/${OG_GETH_SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=0g Geth Node Service - ${OG_GETH_SERVICE_NAME}
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0g-geth \\
  --config $HOME/.0gchaind/geth-config.toml \\
  --datadir $HOME/.0gchaind/0g-home/geth-home \\
  --http \\
  --http.api eth,net,web3,txpool,trace \\
  --http.addr 127.0.0.1 \\
  --http.port ${OG_PORT}545 \\
  --ws \\
  --ws.api eth,web3,net,txpool \\
  --ws.addr 127.0.0.1 \\
  --ws.port ${OG_PORT}546 \\
  --authrpc.port ${OG_PORT}551 \\
  --discovery.port ${OG_PORT}303 \\
  --port ${OG_PORT}303 \\
  --networkid 16661
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    EL_SERVICE_NAME="$OG_GETH_SERVICE_NAME"
else
    # Reth service file
    sudo tee /etc/systemd/system/${OG_RETH_SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=0G Reth Execution Client - ${OG_RETH_SERVICE_NAME}
After=network-online.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0g-reth node \\
  --chain $HOME/.0gchaind/geth-genesis.json \\
  --http \\
  --http.addr 0.0.0.0 \\
  --http.port ${OG_PORT}545 \\
  --http.api eth,net,admin \\
  --authrpc.addr 0.0.0.0 \\
  --authrpc.port ${OG_PORT}551 \\
  --authrpc.jwtsecret $HOME/.0gchaind/jwt.hex \\
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
    EL_SERVICE_NAME="$OG_RETH_SERVICE_NAME"
fi

# ==== START SERVICES ====
sudo systemctl daemon-reload
sudo systemctl enable ${OG_SERVICE_NAME}
sudo systemctl enable ${EL_SERVICE_NAME}

# Start EL first, then CL
echo -e "${CYAN}Starting ${EXEC_CLIENT} execution client...${RESET}"
sudo systemctl start ${EL_SERVICE_NAME}

# For Reth: wait for Engine API port
if [ "$EXEC_CLIENT" = "reth" ]; then
    echo -e "${YELLOW}Waiting for Reth Engine API port (${OG_PORT}551) to be ready...${RESET}"
    for i in $(seq 1 30); do
      if ss -tlnp | grep -q "${OG_PORT}551"; then
        echo -e "${GREEN}Reth Engine API is ready.${RESET}"
        break
      fi
      if [ "$i" -eq 30 ]; then
        echo -e "${YELLOW}Warning: Engine API port not detected after 30s. Starting consensus anyway...${RESET}"
      fi
      sleep 1
    done
fi

echo -e "${CYAN}Starting consensus client...${RESET}"
sudo systemctl start ${OG_SERVICE_NAME}

# Also restart EL after CL for Geth
if [ "$EXEC_CLIENT" = "geth" ]; then
    sudo systemctl restart ${EL_SERVICE_NAME}
fi

# ==== DONE ====
echo -e "\n${GREEN}0G Node Installation Completed Successfully!${RESET}"
echo -e "\n${YELLOW}Node Configuration Summary:${RESET}"
echo -e "Type: ${CYAN}$NODE_TYPE${RESET}"
echo -e "Execution Client: ${CYAN}$EXEC_CLIENT${RESET}"
echo -e "Moniker: ${CYAN}$OG_MONIKER${RESET}"
echo -e "Port Prefix: ${CYAN}$OG_PORT${RESET}"
echo -e "Consensus Service: ${CYAN}${OG_SERVICE_NAME}.service${RESET}"
echo -e "EL Service: ${CYAN}${EL_SERVICE_NAME}.service${RESET}"
echo -e "Indexer: ${CYAN}$([ "$ENABLE_INDEXER" = "yes" ] && echo "Enabled" || echo "Disabled")${RESET}"
[ "$NODE_TYPE" = "validator" ] && echo -e "ETH_RPC_URL: ${CYAN}$ETH_RPC_URL${RESET}\nBLOCK_NUM: ${CYAN}$BLOCK_NUM${RESET}"
echo -e "Node ID: ${CYAN}$(0gchaind comet show-node-id --home $HOME/.0gchaind/0g-home/0gchaind-home/)${RESET}"
echo -e "\nTo view logs: sudo journalctl -u ${OG_SERVICE_NAME} -u ${EL_SERVICE_NAME} -fn 100"
echo -e "\n${YELLOW}Press Enter to continue to main menu...${RESET}"
read -r
