#!/bin/bash
set -euo pipefail

# ==== 0G Mainnet: Rollback & Align CL/EL Height ====
# Guided recovery for fixing height mismatch between CL (0gchaind) and EL (0g-reth).

GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RED="\e[31m"; ORANGE="\e[38;5;214m"; RESET="\e[0m"

echo -e "${ORANGE}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${ORANGE}║${RESET}  ${CYAN}0G Mainnet: Rollback & Align CL/EL Height${RESET}             ${ORANGE}║${RESET}"
echo -e "${ORANGE}║${RESET}  ${YELLOW}Guided recovery for CL/EL height mismatch${RESET}            ${ORANGE}║${RESET}"
echo -e "${ORANGE}╚══════════════════════════════════════════════════════════╝${RESET}"

echo -e "\n${RED}▓▒░ WARNING ░▒▓${RESET}"
echo -e "${YELLOW}This tool will rollback your consensus and/or execution layer.${RESET}"
echo -e "${YELLOW}Only use when your node has a CL/EL height mismatch or forkchoice error.${RESET}"

read -p $'\n\e[33mDo you want to proceed? (yes/no): \e[0m' confirm
if [[ "${confirm,,}" != "yes" ]]; then
    echo -e "${RED}Cancelled.${RESET}"
    exit 0
fi

# Load env
source $HOME/.bash_profile 2>/dev/null || true

# ==== STEP 1: Detect paths ====
echo -e "\n${CYAN}[Step 1/8] Detecting paths and binaries...${RESET}"

# Detect 0gchaind binary
OGCHAIND_BIN="$(command -v 0gchaind 2>/dev/null || true)"
if [ -z "$OGCHAIND_BIN" ]; then
    OGCHAIND_BIN="$(find $HOME/go/bin /usr/local/bin /usr/bin -type f -name 0gchaind 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$OGCHAIND_BIN" ] || [ ! -x "$OGCHAIND_BIN" ]; then
    echo -e "${RED}Error: 0gchaind binary not found.${RESET}"
    exit 1
fi

# Detect 0g-reth binary
OG_RETH_BIN="$(command -v 0g-reth 2>/dev/null || true)"
if [ -z "$OG_RETH_BIN" ]; then
    OG_RETH_BIN="$(find $HOME/go/bin /usr/local/bin /usr/bin $HOME -maxdepth 3 -type f -name 0g-reth 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$OG_RETH_BIN" ] || [ ! -x "$OG_RETH_BIN" ]; then
    echo -e "${YELLOW}Warning: 0g-reth binary not found. EL unwind will be skipped.${RESET}"
    OG_RETH_BIN=""
fi

# Detect CL home
CL_HOME="$HOME/.0gchaind/0g-home/0gchaind-home"
if [ ! -d "$CL_HOME" ]; then
    CL_HOME="$(find $HOME/.0gchaind -type d -name 0gchaind-home 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$CL_HOME" ] || [ ! -d "$CL_HOME" ]; then
    echo -e "${RED}Error: CL home directory not found.${RESET}"
    exit 1
fi

# Detect Reth genesis
GENESIS="$(find $HOME/.0gchaind -type f -name geth-genesis.json 2>/dev/null | head -n 1 || true)"

# Detect Reth datadir
RETH_DATADIR="$(find $HOME/.0gchaind -type d -name reth-home 2>/dev/null | head -n 1 || true)"

# Detect jwt.hex
JWT_FILE="$(find $HOME/.0gchaind -type f -name jwt.hex 2>/dev/null | head -n 1 || true)"
JWT_DIR=""
if [ -n "$JWT_FILE" ]; then
    JWT_DIR="$(dirname "$JWT_FILE")"
fi

# Detect port prefix
OG_PORT="${OG_PORT:-26}"

# Detect service names
CL_SERVICE="${OG_SERVICE_NAME:-0gchaind}"
EL_SERVICE="${OG_RETH_SERVICE_NAME:-0g-reth}"

# Detect Reth HTTP RPC
EL_RPC_URL="http://127.0.0.1:${OG_PORT}545"

echo -e "${GREEN}Detected:${RESET}"
echo -e "  0gchaind binary:  ${CYAN}${OGCHAIND_BIN}${RESET}"
echo -e "  0g-reth binary:   ${CYAN}${OG_RETH_BIN:-not found}${RESET}"
echo -e "  CL home:          ${CYAN}${CL_HOME}${RESET}"
echo -e "  Reth genesis:     ${CYAN}${GENESIS:-not found}${RESET}"
echo -e "  Reth datadir:     ${CYAN}${RETH_DATADIR:-not found}${RESET}"
echo -e "  jwt.hex:          ${CYAN}${JWT_FILE:-not found}${RESET}"
echo -e "  JWT directory:    ${CYAN}${JWT_DIR:-not found}${RESET}"
echo -e "  Reth HTTP RPC:    ${CYAN}${EL_RPC_URL}${RESET}"
echo -e "  CL service:       ${CYAN}${CL_SERVICE}${RESET}"
echo -e "  EL service:       ${CYAN}${EL_SERVICE}${RESET}"

if [ -z "$JWT_FILE" ] || [ -z "$JWT_DIR" ]; then
    echo -e "${RED}Error: jwt.hex not found. CL rollback requires jwt.hex directory.${RESET}"
    exit 1
fi

# ==== STEP 2: Stop CL ====
echo -e "\n${CYAN}[Step 2/8] Stopping consensus client...${RESET}"
sudo systemctl stop ${CL_SERVICE} 2>/dev/null || true
echo -e "${GREEN}Consensus client stopped.${RESET}"

# ==== STEP 3: Detect EL height ====
echo -e "\n${CYAN}[Step 3/8] Detecting local EL height...${RESET}"

EL_HEIGHT=""

# Try local RPC first
EL_HEX=$(curl -s -X POST "$EL_RPC_URL" \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    2>/dev/null | jq -r '.result // empty' 2>/dev/null || true)

if [ -n "$EL_HEX" ] && [ "$EL_HEX" != "null" ]; then
    EL_HEIGHT=$(printf "%d" "$EL_HEX" 2>/dev/null || true)
fi

# Fallback: parse Reth logs
if [ -z "$EL_HEIGHT" ] || [ "$EL_HEIGHT" = "0" ]; then
    echo -e "${YELLOW}Local RPC unavailable. Parsing Reth logs...${RESET}"
    LOG_HEIGHT=$(sudo journalctl -u ${EL_SERVICE} -n 200 --no-pager 2>/dev/null \
        | grep -oE 'latest_block=[0-9]+' | tail -n 1 | grep -oE '[0-9]+' || true)
    if [ -n "$LOG_HEIGHT" ]; then
        EL_HEIGHT="$LOG_HEIGHT"
    fi
fi

if [ -z "$EL_HEIGHT" ] || [ "$EL_HEIGHT" = "0" ]; then
    echo -e "${RED}Could not detect local EL height from RPC or logs.${RESET}"
    read -p "Enter local EL height manually: " EL_HEIGHT
    if ! [[ "$EL_HEIGHT" =~ ^[0-9]+$ ]] || [ "$EL_HEIGHT" -le 0 ]; then
        echo -e "${RED}Invalid height. Aborting.${RESET}"
        exit 1
    fi
fi

echo -e "${GREEN}Local EL height: ${CYAN}${EL_HEIGHT}${RESET}"

# ==== STEP 4: Choose target height ====
echo -e "\n${CYAN}[Step 4/8] Choosing target height...${RESET}"
echo -e "${YELLOW}Default target = local EL height (${EL_HEIGHT})${RESET}"
echo -e "${YELLOW}Do NOT use remote RPC height if your node is far behind.${RESET}"

read -p "Enter target height [default: ${EL_HEIGHT}]: " INPUT_TARGET
TARGET_HEIGHT="${INPUT_TARGET:-$EL_HEIGHT}"

if ! [[ "$TARGET_HEIGHT" =~ ^[0-9]+$ ]] || [ "$TARGET_HEIGHT" -le 0 ]; then
    echo -e "${RED}Invalid target height. Aborting.${RESET}"
    exit 1
fi

# Warn if target > EL
if [ "$TARGET_HEIGHT" -gt "$EL_HEIGHT" ]; then
    echo -e "\n${RED}▓▒░ WARNING ░▒▓${RESET}"
    echo -e "${RED}Target height ($TARGET_HEIGHT) is ABOVE local EL height ($EL_HEIGHT).${RESET}"
    echo -e "${RED}Reth cannot unwind upward. Using EL height ($EL_HEIGHT) instead.${RESET}"
    TARGET_HEIGHT="$EL_HEIGHT"
fi

echo -e "${GREEN}Target height: ${CYAN}${TARGET_HEIGHT}${RESET}"

# ==== STEP 5: Determine actions ====
echo -e "\n${CYAN}[Step 5/8] Planning recovery actions...${RESET}"

WILL_ROLLBACK_CL="yes"
WILL_UNWIND_EL="no"

if [ -n "$OG_RETH_BIN" ] && [ "$EL_HEIGHT" -gt "$TARGET_HEIGHT" ]; then
    WILL_UNWIND_EL="yes"
fi

echo -e "\n${ORANGE}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${ORANGE}║  Planned recovery action:                               ║${RESET}"
echo -e "${ORANGE}╚══════════════════════════════════════════════════════════╝${RESET}"
echo -e "  Target height:                ${CYAN}${TARGET_HEIGHT}${RESET}"
echo -e "  Local EL height:              ${CYAN}${EL_HEIGHT}${RESET}"
echo -e "  Will rollback CL:             ${CYAN}${WILL_ROLLBACK_CL}${RESET}"
echo -e "  Will unwind EL:               ${CYAN}${WILL_UNWIND_EL}${RESET}"
echo -e "  CL rollback working dir:      ${CYAN}${JWT_DIR}${RESET}"
echo -e "  jwt.hex path:                 ${CYAN}${JWT_FILE}${RESET}"

read -p $'\n\e[33mType YES to continue: \e[0m' final_confirm
if [ "$final_confirm" != "YES" ]; then
    echo -e "${RED}Cancelled.${RESET}"
    # Restart CL since we stopped it
    sudo systemctl start ${CL_SERVICE} 2>/dev/null || true
    exit 0
fi

# ==== STEP 6: Rollback CL ====
echo -e "\n${CYAN}[Step 6/8] Rolling back CL to target height ${TARGET_HEIGHT}...${RESET}"

cd "$JWT_DIR"
echo -e "${YELLOW}Working directory: $(pwd)${RESET}"

# First rollback to detect current CL height
ROLLBACK_COUNT=0
MAX_ROLLBACKS=5000

while true; do
    ROLLBACK_COUNT=$((ROLLBACK_COUNT + 1))

    if [ "$ROLLBACK_COUNT" -gt "$MAX_ROLLBACKS" ]; then
        echo -e "${RED}Reached max rollbacks ($MAX_ROLLBACKS). CL may still be above target.${RESET}"
        echo -e "${YELLOW}You can rerun this script to continue.${RESET}"
        break
    fi

    OUT=$("$OGCHAIND_BIN" rollback --hard --home "$CL_HOME" --chaincfg.chain-spec mainnet 2>&1) || true
    echo "$OUT"

    # Parse height from output
    CL_HEIGHT=$(echo "$OUT" | sed -n 's/.*height=\([0-9][0-9]*\).*/\1/p' | tail -n 1)

    # Fallback parsing
    if [ -z "$CL_HEIGHT" ]; then
        CL_HEIGHT=$(echo "$OUT" | grep -oE 'height[= :]+[0-9]+' | grep -oE '[0-9]+' | tail -n 1 || true)
    fi

    if [ -z "$CL_HEIGHT" ]; then
        echo -e "${RED}Could not parse CL height from rollback output.${RESET}"
        break
    fi

    echo -e "  ${CYAN}Rollback #${ROLLBACK_COUNT} | CL height: ${CL_HEIGHT} | Target: ${TARGET_HEIGHT}${RESET}"

    if [ "$CL_HEIGHT" -le "$TARGET_HEIGHT" ]; then
        echo -e "${GREEN}CL reached target height: ${CL_HEIGHT}${RESET}"
        break
    fi

    sleep 0.5
done

# ==== STEP 7: Handle EL ====
echo -e "\n${CYAN}[Step 7/8] Handling EL (Reth)...${RESET}"

if [ "$WILL_UNWIND_EL" = "yes" ]; then
    echo -e "${YELLOW}Stopping EL service for unwind...${RESET}"
    sudo systemctl stop ${EL_SERVICE} 2>/dev/null || true

    echo -e "${YELLOW}Running: 0g-reth stage unwind to-block ${TARGET_HEIGHT}${RESET}"
    "$OG_RETH_BIN" stage unwind \
        --chain "$GENESIS" \
        --datadir "$RETH_DATADIR" \
        to-block "$TARGET_HEIGHT" || {
        echo -e "${RED}Reth unwind failed. Check manually.${RESET}"
    }

    echo -e "${GREEN}Reth unwind completed.${RESET}"
else
    if [ "$EL_HEIGHT" -eq "$TARGET_HEIGHT" ]; then
        echo -e "${GREEN}EL already at target height. No unwind needed.${RESET}"
    elif [ "$EL_HEIGHT" -lt "$TARGET_HEIGHT" ]; then
        echo -e "${GREEN}EL ($EL_HEIGHT) is below target ($TARGET_HEIGHT). No unwind needed.${RESET}"
        echo -e "${YELLOW}Reth will sync upward after restart.${RESET}"
    fi
fi

# ==== STEP 8: Restart services ====
echo -e "\n${CYAN}[Step 8/8] Starting services (EL first, then CL)...${RESET}"

echo -e "${YELLOW}Starting EL (${EL_SERVICE})...${RESET}"
sudo systemctl start ${EL_SERVICE}

# Wait for Engine API
echo -e "${YELLOW}Waiting for Reth Engine API port (${OG_PORT}551)...${RESET}"
for i in $(seq 1 30); do
    if ss -tlnp | grep -q "${OG_PORT}551"; then
        echo -e "${GREEN}Reth Engine API is ready.${RESET}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo -e "${YELLOW}Warning: Engine API not detected after 30s. Starting CL anyway...${RESET}"
    fi
    sleep 1
done

echo -e "${YELLOW}Starting CL (${CL_SERVICE})...${RESET}"
sudo systemctl start ${CL_SERVICE}

echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║  Recovery completed.                                    ║${RESET}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo -e "\n${YELLOW}Final alignment target:${RESET}"
echo -e "  CL height: ${CYAN}${TARGET_HEIGHT}${RESET}"
echo -e "  EL height: ${CYAN}${TARGET_HEIGHT}${RESET}"
echo -e "\n${YELLOW}Restart order:${RESET}"
echo -e "  1. ${EL_SERVICE} started first"
echo -e "  2. ${CL_SERVICE} started after EL became healthy"
echo -e "\n${YELLOW}Monitor logs:${RESET}"
echo -e "  sudo journalctl -u ${EL_SERVICE} -f -n 100"
echo -e "  sudo journalctl -u ${CL_SERVICE} -f -n 100"

echo -e "\n${YELLOW}Press Enter to return to menu...${RESET}"
read -r
