#!/bin/bash
set -euo pipefail

# ==== 0G Mainnet: Rollback & Align CL/EL Height ====
# Guided recovery for fixing height mismatch between CL (0gchaind) and EL (0g-reth).

rollback_align_cl_el() {
    local GREEN="\e[32m" YELLOW="\e[33m" CYAN="\e[36m" RED="\e[31m" ORANGE="\e[38;5;214m" RESET="\e[0m"

    echo -e "${ORANGE}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${ORANGE}║${RESET}  ${CYAN}0G Mainnet: Rollback & Align CL/EL Height${RESET}             ${ORANGE}║${RESET}"
    echo -e "${ORANGE}║${RESET}  ${YELLOW}Guided recovery for CL/EL height mismatch${RESET}            ${ORANGE}║${RESET}"
    echo -e "${ORANGE}╚══════════════════════════════════════════════════════════╝${RESET}"

    echo -e "\n${RED}▓▒░ WARNING ░▒▓${RESET}"
    echo -e "${YELLOW}This tool will rollback your consensus and/or execution layer.${RESET}"
    echo -e "${YELLOW}Only use when your node has a CL/EL height mismatch or forkchoice error.${RESET}"

    local confirm
    read -p $'\n\e[33mDo you want to proceed? (yes/no): \e[0m' confirm
    if [[ "${confirm,,}" != "yes" ]]; then
        echo -e "${RED}Cancelled.${RESET}"
        return 0
    fi

    # Load env
    source $HOME/.bash_profile 2>/dev/null || true

    # ==== STEP 1: Detect paths ====
    echo -e "\n${CYAN}[Step 1/8] Detecting paths and binaries...${RESET}"

    # Detect 0gchaind binary
    local OGCHAIND_BIN
    OGCHAIND_BIN="$(command -v 0gchaind 2>/dev/null || true)"
    if [ -z "$OGCHAIND_BIN" ]; then
        OGCHAIND_BIN="$(find $HOME/go/bin /usr/local/bin /usr/bin -type f -name 0gchaind 2>/dev/null | head -n 1 || true)"
    fi
    if [ -z "$OGCHAIND_BIN" ] || [ ! -x "$OGCHAIND_BIN" ]; then
        echo -e "${RED}Error: 0gchaind binary not found.${RESET}"
        return 1
    fi

    # Detect 0g-reth binary
    local OG_RETH_BIN
    OG_RETH_BIN="$(command -v 0g-reth 2>/dev/null || true)"
    if [ -z "$OG_RETH_BIN" ]; then
        OG_RETH_BIN="$(find $HOME/go/bin /usr/local/bin /usr/bin $HOME -maxdepth 3 -type f -name 0g-reth 2>/dev/null | head -n 1 || true)"
    fi
    if [ -z "$OG_RETH_BIN" ] || [ ! -x "$OG_RETH_BIN" ]; then
        echo -e "${YELLOW}Warning: 0g-reth binary not found. EL unwind will be skipped.${RESET}"
        OG_RETH_BIN=""
    fi

    # Detect CL home
    local CL_HOME
    CL_HOME="$HOME/.0gchaind/0g-home/0gchaind-home"
    if [ ! -d "$CL_HOME" ]; then
        CL_HOME="$(find $HOME/.0gchaind -type d -name 0gchaind-home 2>/dev/null | head -n 1 || true)"
    fi
    if [ -z "$CL_HOME" ] || [ ! -d "$CL_HOME" ]; then
        echo -e "${RED}Error: CL home directory not found.${RESET}"
        return 1
    fi

    # Detect Reth genesis
    local GENESIS
    GENESIS="$(find $HOME/.0gchaind -type f -name geth-genesis.json 2>/dev/null | head -n 1 || true)"

    # Detect Reth datadir
    local RETH_DATADIR
    RETH_DATADIR="$(find $HOME/.0gchaind -type d -name reth-home 2>/dev/null | head -n 1 || true)"

    # Validate GENESIS and RETH_DATADIR if Reth exists
    if [ -n "$OG_RETH_BIN" ]; then
        if [ -z "$GENESIS" ] || [ ! -f "$GENESIS" ]; then
            echo -e "${YELLOW}Warning: geth-genesis.json not found. EL unwind will be unavailable.${RESET}"
            OG_RETH_BIN=""
        fi

        if [ -z "$RETH_DATADIR" ] || [ ! -d "$RETH_DATADIR" ]; then
            echo -e "${YELLOW}Warning: reth-home not found. EL unwind will be unavailable.${RESET}"
            OG_RETH_BIN=""
        fi
    fi

    # Detect jwt.hex
    local JWT_FILE
    JWT_FILE="$(find $HOME/.0gchaind -type f -name jwt.hex 2>/dev/null | head -n 1 || true)"
    local JWT_DIR=""
    if [ -n "$JWT_FILE" ]; then
        JWT_DIR="$(dirname "$JWT_FILE")"
    fi

    if [ -z "$JWT_FILE" ] || [ -z "$JWT_DIR" ] || [ ! -f "$JWT_DIR/jwt.hex" ]; then
        echo -e "${RED}Error: jwt.hex not found. CL rollback requires jwt.hex directory.${RESET}"
        return 1
    fi

    # Detect port prefix
    local OG_PORT
    OG_PORT="${OG_PORT:-26}"

    # Detect service names
    local CL_SERVICE EL_SERVICE
    CL_SERVICE="${OG_SERVICE_NAME:-0gchaind}"
    EL_SERVICE="${OG_RETH_SERVICE_NAME:-0g-reth}"

    echo -e "${GREEN}Detected:${RESET}"
    echo -e "  0gchaind binary:  ${CYAN}${OGCHAIND_BIN}${RESET}"
    echo -e "  0g-reth binary:   ${CYAN}${OG_RETH_BIN:-not found/disabled}${RESET}"
    echo -e "  CL home:          ${CYAN}${CL_HOME}${RESET}"
    echo -e "  Reth genesis:     ${CYAN}${GENESIS:-not found}${RESET}"
    echo -e "  Reth datadir:     ${CYAN}${RETH_DATADIR:-not found}${RESET}"
    echo -e "  jwt.hex:          ${CYAN}${JWT_FILE}${RESET}"
    echo -e "  JWT directory:    ${CYAN}${JWT_DIR}${RESET}"
    echo -e "  CL service:       ${CYAN}${CL_SERVICE}${RESET}"
    echo -e "  EL service:       ${CYAN}${EL_SERVICE}${RESET}"

    # ==== STEP 2: Detect EL height ====
    echo -e "\n${CYAN}[Step 2/8] Detecting local EL height...${RESET}"

    local EL_HEIGHT=""
    local EL_RPC_URL=""
    local EL_RPC_CANDIDATES
    EL_RPC_CANDIDATES=(
      "http://127.0.0.1:${OG_PORT}545"
      "http://127.0.0.1:28545"
      "http://127.0.0.1:26545"
      "http://127.0.0.1:8545"
    )

    local rpc el_hex
    for rpc in "${EL_RPC_CANDIDATES[@]}"; do
        el_hex=$(curl -s -X POST "$rpc" \
            -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            2>/dev/null | jq -r '.result // empty' 2>/dev/null || true)

        if [ -n "$el_hex" ] && [ "$el_hex" != "null" ]; then
            EL_HEIGHT=$(printf "%d" "$el_hex" 2>/dev/null || true)
            if [ -n "$EL_HEIGHT" ] && [ "$EL_HEIGHT" != "0" ]; then
                EL_RPC_URL="$rpc"
                break
            fi
        fi
    done

    # Fallback: parse Reth logs
    if [ -z "$EL_HEIGHT" ] || [ "$EL_HEIGHT" = "0" ]; then
        echo -e "${YELLOW}Local RPC candidates unavailable. Parsing Reth logs...${RESET}"
        local log_height
        log_height=$(sudo journalctl -u ${EL_SERVICE} -n 200 --no-pager 2>/dev/null \
            | grep -oE 'latest_block=[0-9]+' | tail -n 1 | grep -oE '[0-9]+' || true)
        if [ -n "$log_height" ]; then
            EL_HEIGHT="$log_height"
        fi
    fi

    if [ -z "$EL_HEIGHT" ] || [ "$EL_HEIGHT" = "0" ]; then
        echo -e "${RED}Could not detect local EL height from RPC or logs.${RESET}"
        echo -e "${YELLOW}Please check your local EL (Reth) logs to find the latest block number.${RESET}"
        echo -e "  Run this command in another terminal: ${CYAN}sudo journalctl -u ${EL_SERVICE} -n 50 --no-pager${RESET}"
        echo -e "  Look for ${CYAN}'latest_block=XXXXX'${RESET} or similar."
        echo -e "${RED}Do NOT use the consensus (CL/0gchaind) height (e.g., appHeight/stateHeight from 0gchaind replay logs) as the EL height.${RESET}"
        read -p "Enter local EL height manually: " EL_HEIGHT
        if ! [[ "$EL_HEIGHT" =~ ^[0-9]+$ ]] || [ "$EL_HEIGHT" -le 0 ]; then
            echo -e "${RED}Invalid height. Aborting.${RESET}"
            return 1
        fi
    fi

    echo -e "${GREEN}Local EL height: ${CYAN}${EL_HEIGHT}${RESET}"
    if [ -n "$EL_RPC_URL" ]; then
        echo -e "  Using EL RPC:     ${CYAN}${EL_RPC_URL}${RESET}"
    fi

    # ==== STEP 3: Detect CL height ====
    echo -e "\n${CYAN}[Step 3/8] Detecting local CL height...${RESET}"

    local parsed_cl_port=""
    if [ -f "$CL_HOME/config/config.toml" ]; then
        parsed_cl_port=$(grep -oP 'laddr = "tcp://(0.0.0.0|127.0.0.1):\K[0-9]+' "$CL_HOME/config/config.toml" 2>/dev/null | tail -n 1 || true)
    fi

    local CL_RPC_CANDIDATES
    CL_RPC_CANDIDATES=()
    if [ -n "$parsed_cl_port" ]; then
        CL_RPC_CANDIDATES+=("http://127.0.0.1:${parsed_cl_port}")
    fi
    CL_RPC_CANDIDATES+=(
        "http://127.0.0.1:${OG_PORT}657"
        "http://127.0.0.1:28657"
        "http://127.0.0.1:26657"
    )

    local CL_HEIGHT=""
    local CL_RPC_URL=""
    local cl_rpc cl_status_res
    for cl_rpc in "${CL_RPC_CANDIDATES[@]}"; do
        cl_status_res=$(curl -s "$cl_rpc/status" 2>/dev/null || true)
        CL_HEIGHT=$(echo "$cl_status_res" | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)
        if [ -n "$CL_HEIGHT" ] && [[ "$CL_HEIGHT" =~ ^[0-9]+$ ]] && [ "$CL_HEIGHT" -gt 0 ]; then
            CL_RPC_URL="$cl_rpc"
            break
        fi
    done

    if [ -z "$CL_HEIGHT" ] || ! [[ "$CL_HEIGHT" =~ ^[0-9]+$ ]] || [ "$CL_HEIGHT" -le 0 ]; then
        echo -e "${YELLOW}Could not detect CL height from local CL RPC candidates.${RESET}"
        read -p "Enter current local CL height manually: " CL_HEIGHT
    fi

    if ! [[ "$CL_HEIGHT" =~ ^[0-9]+$ ]] || [ "$CL_HEIGHT" -le 0 ]; then
        echo -e "${RED}Invalid CL height. Aborting.${RESET}"
        return 1
    fi

    echo -e "${GREEN}Local CL height: ${CYAN}${CL_HEIGHT}${RESET}"
    if [ -n "$CL_RPC_URL" ]; then
        echo -e "  Using CL RPC:     ${CYAN}${CL_RPC_URL}${RESET}"
    fi

    # ==== STEP 4: Choose target height ====
    echo -e "\n${CYAN}[Step 4/8] Choosing target height...${RESET}"
    echo -e "${YELLOW}Default target = local EL height (${EL_HEIGHT})${RESET}"
    echo -e "${YELLOW}Do NOT use remote RPC height if your node is far behind.${RESET}"

    local input_target target_height
    read -p "Enter target height [default: ${EL_HEIGHT}]: " input_target
    target_height="${input_target:-$EL_HEIGHT}"

    if ! [[ "$target_height" =~ ^[0-9]+$ ]] || [ "$target_height" -le 0 ]; then
        echo -e "${RED}Invalid target height. Aborting.${RESET}"
        return 1
    fi

    # Warn if target > EL
    if [ "$target_height" -gt "$EL_HEIGHT" ]; then
        echo -e "\n${RED}▓▒░ WARNING ░▒▓${RESET}"
        echo -e "${RED}Target height ($target_height) is ABOVE local EL height ($EL_HEIGHT).${RESET}"
        echo -e "${RED}Reth cannot unwind upward. Using EL height ($EL_HEIGHT) instead.${RESET}"
        target_height="$EL_HEIGHT"
    fi

    echo -e "${GREEN}Target height: ${CYAN}${target_height}${RESET}"

    # ==== STEP 5: Determine actions ====
    echo -e "\n${CYAN}[Step 5/8] Planning recovery actions...${RESET}"

    local will_rollback_cl="no"
    local will_unwind_el="no"

    if [ "$CL_HEIGHT" -gt "$target_height" ]; then
        will_rollback_cl="yes"
    fi

    if [ -n "$OG_RETH_BIN" ] && [ "$EL_HEIGHT" -gt "$target_height" ]; then
        will_unwind_el="yes"
    fi

    echo -e "\n${ORANGE}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${ORANGE}║  Planned recovery action:                               ║${RESET}"
    echo -e "${ORANGE}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo -e "  Target height:                ${CYAN}${target_height}${RESET}"
    echo -e "  Local CL height:              ${CYAN}${CL_HEIGHT}${RESET}"
    echo -e "  Local EL height:              ${CYAN}${EL_HEIGHT}${RESET}"
    echo -e "  Will rollback CL:             ${CYAN}${will_rollback_cl}${RESET}"
    echo -e "  Will unwind EL:               ${CYAN}${will_unwind_el}${RESET}"
    echo -e "  CL rollback working dir:      ${CYAN}${JWT_DIR}${RESET}"
    echo -e "  jwt.hex path:                 ${CYAN}${JWT_FILE}${RESET}"

    if [ "$will_rollback_cl" = "no" ] && [ "$will_unwind_el" = "no" ]; then
        echo -e "\n${GREEN}Both CL and EL are already at or below target height. No action needed.${RESET}"
        return 0
    fi

    local final_confirm
    read -p $'\n\e[33mType YES to continue: \e[0m' final_confirm
    if [ "$final_confirm" != "YES" ]; then
        echo -e "${RED}Cancelled.${RESET}"
        return 0
    fi

    # ==== STEP 6: Stop services ====
    echo -e "\n${CYAN}[Step 6/8] Stopping both services...${RESET}"
    echo -e "${YELLOW}Stopping CL (${CL_SERVICE})...${RESET}"
    sudo systemctl stop ${CL_SERVICE} 2>/dev/null || true
    echo -e "${YELLOW}Stopping EL (${EL_SERVICE})...${RESET}"
    sudo systemctl stop ${EL_SERVICE} 2>/dev/null || true
    echo -e "${GREEN}Both services stopped.${RESET}"

    # ==== STEP 7: Rollback CL ====
    if [ "$will_rollback_cl" = "yes" ]; then
        echo -e "\n${CYAN}[Step 7a/8] Rolling back CL to target height ${target_height}...${RESET}"

        cd "$JWT_DIR"
        echo -e "${YELLOW}Working directory: $(pwd)${RESET}"

        local rollback_count=0
        local max_rollbacks=5000
        local out new_cl_height

        while [ "$CL_HEIGHT" -gt "$target_height" ]; do
            rollback_count=$((rollback_count + 1))

            if [ "$rollback_count" -gt "$max_rollbacks" ]; then
                echo -e "${RED}Reached max rollbacks ($max_rollbacks). CL may still be above target.${RESET}"
                break
            fi

            echo "Running CL rollback..."
            out=$("$OGCHAIND_BIN" rollback --hard --home "$CL_HOME" --chaincfg.chain-spec mainnet 2>&1) || true
            echo "$out"

            # Parse height from output
            new_cl_height=$(echo "$out" | sed -n 's/.*height=\([0-9][0-9]*\).*/\1/p' | tail -n 1)

            # Fallback parsing
            if [ -z "$new_cl_height" ]; then
                new_cl_height=$(echo "$out" | grep -oE 'height[= :]+[0-9]+' | grep -oE '[0-9]+' | tail -n 1 || true)
            fi

            if [ -z "$new_cl_height" ]; then
                echo -e "${RED}Could not parse CL height from rollback output.${RESET}"
                break
            fi

            CL_HEIGHT="$new_cl_height"
            echo "Rollback result CL height: $CL_HEIGHT | Target: $target_height"

            if [ "$CL_HEIGHT" = "$target_height" ]; then
                echo "CL reached target height: $target_height"
                break
            fi

            if [ -n "$CL_HEIGHT" ] && [ "$CL_HEIGHT" -lt "$target_height" ]; then
                echo "CL went below target. Stop here."
                break
            fi

            sleep 1
        done
    else
        echo -e "\n${GREEN}CL already at or below target height. Skipping CL rollback.${RESET}"
    fi

    # ==== STEP 8: Handle EL ====
    echo -e "\n${CYAN}[Step 7b/8] Handling EL (Reth)...${RESET}"

    if [ "$will_unwind_el" = "yes" ]; then
        echo -e "${YELLOW}Running: 0g-reth stage unwind to-block ${target_height}${RESET}"
        if ! "$OG_RETH_BIN" stage unwind \
            --chain "$GENESIS" \
            --datadir "$RETH_DATADIR" \
            to-block "$target_height"; then
            echo -e "${RED}Reth unwind failed. Stop here and check manually.${RESET}"
            return 1
        fi

        echo -e "${GREEN}Reth unwind completed.${RESET}"
    else
        if [ "$EL_HEIGHT" -eq "$target_height" ]; then
            echo -e "${GREEN}EL already at target height. No unwind needed.${RESET}"
        elif [ "$EL_HEIGHT" -lt "$target_height" ]; then
            echo -e "${GREEN}EL ($EL_HEIGHT) is below target ($target_height). No unwind needed.${RESET}"
            echo -e "${YELLOW}Reth will sync upward after restart.${RESET}"
        fi
    fi

    # ==== STEP 9: Restart services ====
    echo -e "\n${CYAN}[Step 8/8] Starting services (EL first, then CL)...${RESET}"

    echo -e "${YELLOW}Starting EL (${EL_SERVICE})...${RESET}"
    sudo systemctl start ${EL_SERVICE}

    # Parse --authrpc.port from service file
    local parsed_engine_port=""
    local svc_file
    svc_file=$(systemctl show -p FragmentPath "${EL_SERVICE}" 2>/dev/null | cut -d= -f2 || true)
    if [ -n "$svc_file" ] && [ -f "$svc_file" ]; then
        parsed_engine_port=$(grep -oP '--authrpc.port\s+\K[0-9]+' "$svc_file" 2>/dev/null | tail -n 1 || true)
        if [ -z "$parsed_engine_port" ]; then
            parsed_engine_port=$(grep -oE '--authrpc.port[ =][0-9]+' "$svc_file" 2>/dev/null | grep -oE '[0-9]+' | tail -n 1 || true)
        fi
    fi

    # Build Engine API port candidates
    local engine_port_candidates
    engine_port_candidates=()
    if [ -n "$parsed_engine_port" ]; then
        engine_port_candidates+=("$parsed_engine_port")
    fi
    engine_port_candidates+=(
        "${OG_PORT}551"
        "28551"
        "26551"
        "8551"
    )

    # Wait for Engine API
    echo -e "${YELLOW}Waiting for Reth Engine API port to be ready...${RESET}"
    local i p api_ready="no" detected_engine_port=""
    for i in $(seq 1 30); do
        for p in "${engine_port_candidates[@]}"; do
            if ss -tlnp 2>/dev/null | grep -qE ":$p\b"; then
                detected_engine_port="$p"
                api_ready="yes"
                break 2
            fi
        done
        sleep 1
    done

    if [ "$api_ready" != "yes" ]; then
        echo -e "${RED}Engine API not detected after 30s (tried ports: ${engine_port_candidates[*]}).${RESET}"
        echo -e "${YELLOW}Do not start CL yet. Check EL logs first:${RESET}"
        echo -e "  sudo journalctl -u ${EL_SERVICE} -f -n 100"
        return 1
    fi

    echo -e "${GREEN}Reth Engine API is ready on port ${detected_engine_port}.${RESET}"

    echo -e "${YELLOW}Starting CL (${CL_SERVICE})...${RESET}"
    sudo systemctl start ${CL_SERVICE}

    echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║  Recovery completed.                                    ║${RESET}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo -e "\n${YELLOW}Final alignment target:${RESET}"
    echo -e "  CL height: ${CYAN}${target_height}${RESET}"
    echo -e "  EL height: ${CYAN}${target_height}${RESET}"
    echo -e "\n${YELLOW}Restart order:${RESET}"
    echo -e "  1. ${EL_SERVICE} started first"
    echo -e "  2. ${CL_SERVICE} started after EL became healthy"
    echo -e "\n${YELLOW}Monitor logs:${RESET}"
    echo -e "  sudo journalctl -u ${EL_SERVICE} -f -n 100"
    echo -e "  sudo journalctl -u ${CL_SERVICE} -f -n 100"

    echo -e "\n${YELLOW}Press Enter to return to menu...${RESET}"
    read -r
}

# Run the function with all passed arguments
rollback_align_cl_el "$@"
