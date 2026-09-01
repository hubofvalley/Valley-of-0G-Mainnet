#!/bin/bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
ORANGE='\033[38;5;214m'
RESET='\033[0m'

# Menu helper transport. Local checkouts execute sibling files; remote menu runs
# fetch the helper, manifest, and shared manifest loader from the same source ref.
# Managed upstream code/artifacts are then resolved only from immutable values in
# VERSIONS.json. VALLEY_SOURCE_REF may be set to a reviewed commit after release.
VALLEY_REPOSITORY="hubofvalley/Valley-of-0G-Mainnet"
VALLEY_SOURCE_REF="${VALLEY_SOURCE_REF:-main}"

run_repository_script() {
    local relative_path=$1
    shift
    local script_dir local_script local_manifest local_library
    local tmpdir remote_script remote_manifest remote_library rc

    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
    local_script="${script_dir}/${relative_path#resources/}"
    local_manifest="${script_dir}/../VERSIONS.json"
    local_library="${script_dir}/valley_manifest.sh"
    if [ -n "$script_dir" ] && [ -f "$local_script" ] && [ -f "$local_manifest" ] && [ -f "$local_library" ]; then
        VALLEY_MANIFEST_PATH="$local_manifest" VALLEY_MANIFEST_LIB="$local_library"             bash "$local_script" "$@"
        return $?
    fi

    command -v curl >/dev/null 2>&1 || {
        echo "Managed helper blocked: curl is required." >&2
        return 2
    }
    tmpdir=$(mktemp -d)
    remote_script="$tmpdir/helper.sh"
    remote_manifest="$tmpdir/VERSIONS.json"
    remote_library="$tmpdir/valley_manifest.sh"
    if ! curl -fsSL "https://raw.githubusercontent.com/${VALLEY_REPOSITORY}/${VALLEY_SOURCE_REF}/${relative_path}" -o "$remote_script"        || ! curl -fsSL "https://raw.githubusercontent.com/${VALLEY_REPOSITORY}/${VALLEY_SOURCE_REF}/VERSIONS.json" -o "$remote_manifest"        || ! curl -fsSL "https://raw.githubusercontent.com/${VALLEY_REPOSITORY}/${VALLEY_SOURCE_REF}/resources/valley_manifest.sh" -o "$remote_library"; then
        rm -rf "$tmpdir"
        echo "Managed helper download failed; nothing was executed." >&2
        return 2
    fi
    chmod +x "$remote_script"
    VALLEY_MANIFEST_PATH="$remote_manifest" VALLEY_MANIFEST_LIB="$remote_library"         bash "$remote_script" "$@"
    rc=$?
    rm -rf "$tmpdir"
    return "$rc"
}

# Service Name Detection - Ask Once, Remember Forever
source $HOME/.bash_profile 2>/dev/null

if [ -z "${OG_SERVICE_NAME:-}" ]; then
    echo -e "${YELLOW}Service name configuration not found.${RESET}"
    read -p "Enter Consensus Service Name (default '0gchaind'): " INPUT_SVC
    OG_SERVICE_NAME=${INPUT_SVC:-0gchaind}
    echo "export OG_SERVICE_NAME=\"$OG_SERVICE_NAME\"" >> $HOME/.bash_profile
    export OG_SERVICE_NAME
fi

# Detect execution client
EXEC_CLIENT="${EXEC_CLIENT:-geth}"

if [ "$EXEC_CLIENT" = "geth" ]; then
    if [ -z "${OG_GETH_SERVICE_NAME:-}" ]; then
        read -p "Enter Geth Service Name (default '0g-geth'): " INPUT_GETH
        OG_GETH_SERVICE_NAME=${INPUT_GETH:-0g-geth}
        echo "export OG_GETH_SERVICE_NAME=\"$OG_GETH_SERVICE_NAME\"" >> $HOME/.bash_profile
        export OG_GETH_SERVICE_NAME
    fi
else
    if [ -z "${OG_RETH_SERVICE_NAME:-}" ]; then
        read -p "Enter Reth Service Name (default '0g-reth'): " INPUT_RETH
        OG_RETH_SERVICE_NAME=${INPUT_RETH:-0g-reth}
        echo "export OG_RETH_SERVICE_NAME=\"$OG_RETH_SERVICE_NAME\"" >> $HOME/.bash_profile
        export OG_RETH_SERVICE_NAME
    fi
fi

LOGO="
 __      __     _  _                        __    ___    _____ 
 \ \    / /    | || |                      / _|  / _ \  / ____|
  \ \  / /__ _ | || |  ___  _   _    ___  | |_  | | | || |  __ 
  _\ \/ // __ || || | / _ \| | | |  / _ \ |  _| | | | || | |_ |
 | |\  /| (_| || || ||  __/| |_| | | (_) || |   | |_| || |__| |
 | |_\/  \__,_||_||_| \___| \__, |  \___/ |_|    \___/  \_____|
 | '_ \ | | | |              __/ |                             
 | |_) || |_| |             |___/                              
 |____/  \__, |                                                
          __/ |                                                
         |___/                                                 
 __                                   
/__ __ __ __   _|   \  / __ | |  _    
\_| | (_| | | (_|    \/ (_| | | (/_ \/
                                    /
"

INTRO="
Valley of 0G Mainnet by ${ORANGE}Grand Valley${RESET}

${GREEN}0G Validator Node System Requirements${RESET}
${YELLOW}| Category  | Requirements                   |
| --------- | ------------------------------ |
| CPU       | 8 cores                        |
| RAM       | 64+ GB                         |
| Storage   | 1+ TB NVMe SSD                 |
| Bandwidth | 100 Mbps for Download / Upload |${RESET}

validator node current binaries version: ${CYAN}v1.0.6${RESET}
- consensus client service file name: ${CYAN}\${OG_SERVICE_NAME}.service${RESET}
- $([ "${EXEC_CLIENT:-geth}" = "reth" ] && echo "reth service file name: \${CYAN}\${OG_RETH_SERVICE_NAME}.service" || echo "0g-geth service file name: \${CYAN}\${OG_GETH_SERVICE_NAME}.service")${RESET}
current chain : ${CYAN}0gchain-16661 (Aristotle)${RESET}

------------------------------------------------------------------

${GREEN}Storage Node System Requirements${RESET}
${YELLOW}| Category  | Requirements                   |
| --------- | ------------------------------ |
| CPU       | 8+ cores                       |
| RAM       | 32+ GB                         |
| Storage   | 500GB / 1TB NVMe SSD           |
| Bandwidth | 100 Mbps for Download / Upload |${RESET}

storage node current binary version: ${CYAN}v1.1.0${RESET}

------------------------------------------------------------------

${GREEN}Storage KV System Requirements${RESET}
${YELLOW}| Category | Requirements                                |
| -------- | ------------------------------------------- |
| CPU      | 8+ cores                                    |
| RAM      | 32+ GB                                      |
| Storage  | Matches the size of kv streams it maintains |${RESET}

storage kvs current binary version: ${CYAN}v1.4.0${RESET}

------------------------------------------------------------------
"

PRIVACY_SAFETY_STATEMENT="
${YELLOW}Privacy and Safety Statement${RESET}

${GREEN}No User Data Stored Externally${RESET}
- This script does not store any user data externally. All operations are performed locally on your machine.

${GREEN}No Phishing Links${RESET}
- This script does not contain any phishing links. All URLs and commands are provided for legitimate purposes related to 0G validator node operations.

${GREEN}Security Best Practices${RESET}
- Always verify the integrity of the script and its source.
- Ensure you are running the script in a secure environment.
- Be cautious when entering sensitive information such as wallet names and addresses.

${GREEN}Disclaimer${RESET}
- The authors of this script are not responsible for any misuse or damage caused by the use of this script.

${GREEN}Contact${RESET}
- If you have any concerns or questions, please contact us at letsbuidltogether@grandvalleys.com.
"

ENDPOINTS="${GREEN}
Grand Valley 0G public endpoints:${RESET}
- cosmos-rpc: ${BLUE}https://lightnode-rpc-mainnet-0g.grandvalleys.com${RESET}
- evm-rpc: ${BLUE}https://lightnode-json-rpc-mainnet-0g.grandvalleys.com${RESET}
- cosmos rest-api: ${BLUE}https://lightnode-api-mainnet-0g.grandvalleys.com${RESET}
- cosmos ws: ${BLUE}wss://lightnode-rpc-mainnet-0g.grandvalleys.com/websocket${RESET}
- evm ws: ${BLUE}wss://lightnode-wss-mainnet-0g.grandvalleys.com${RESET}
- peer: ${BLUE}813aeda202eae52b0d3e389a0e6e3a0354ad547a@peer-mainnet-0g.grandvalleys.com:28656${RESET}
- enode: ${BLUE}enode://4e600c6ad1e7c7c4ca92c4b1750bba35912551aee16d5eb58fdd8f8b1720cb930fb4903ca54b3df45d92bd4c88bd4583d739a4471b76975c1d09ea56ce5fd8b0@enode-mainnet-0g.grandvalleys.com:28303${RESET}

${GREEN}Grand Valley 0G Mainnet validator profile links:${RESET}
    - ${ORANGE}https://explorer.0g.ai/mainnet/validators/0x108e619da0cdba8a301a53948a4acc23a3d79377/delegators${RESET}
    - ${ORANGE}https://chainscan.0g.ai/address/0x108e619da0cdba8a301a53948a4acc23a3d79377${RESET}

${GREEN}Connect with Zero Gravity (0G):${RESET}
- Official Website: ${BLUE}https://0g.ai/${RESET}
- X: ${BLUE}https://x.com/0G_labs${RESET}
- Official Docs: ${BLUE}https://docs.0g.ai/${RESET}
- Official Discord: ${BLUE}https://discord.gg/0glabs${RESET}
- Official GitHub: ${BLUE}https://github.com/0gfoundation${RESET}
- Official Telegram: ${BLUE}https://t.me/web3_0glabs${RESET}
- Official Explorer: ${BLUE}https://explorer.0g.ai/${RESET}

${GREEN}Connect with Grand Valley:${RESET}
- X: ${BLUE}https://x.com/bacvalley${RESET}
- GitHub: ${BLUE}https://github.com/hubofvalley${RESET}
- 0G Mainnet Guide on GitHub by Grand Valley: ${BLUE}https://github.com/hubofvalley/Mainnet-Guides/tree/main/0g%20(zero-gravity)${RESET}
- Email: ${BLUE}letsbuidltogether@grandvalleys.com${RESET}
"

# Display LOGO and wait for user input to continue
echo -e "$LOGO"
echo -e "$PRIVACY_SAFETY_STATEMENT"
echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
read -r

# Display INTRO section and wait for user input to continue
echo -e "$INTRO"
echo -e "$ENDPOINTS"
echo -e "${YELLOW}\nPress Enter to continue${RESET}"
read -r
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bash_profile
source $HOME/.bash_profile

# Validator Node Functions
function deploy_validator_node() {
    clear
    echo -e "${RED}▓▒░ IMPORTANT DISCLAIMER AND TERMS ░▒▓${RESET}"
    echo -e "${YELLOW}1. SECURITY:${RESET}"
    echo -e "- This script ${GREEN}DOES NOT${RESET} send any data outside your server"
    echo "- All operations are performed locally"
    echo "- You are encouraged to audit the script at:"
    echo -e "  ${BLUE}https://github.com/hubofvalley/Valley-of-0G-Mainnet/blob/main/resources/0g_validator_node_aristotle_install.sh${RESET}"

    echo -e "\n${YELLOW}2. SYSTEM IMPACT:${RESET}"
    echo -e "${GREEN}New Services:${RESET}"
    echo -e "  • ${CYAN}${OG_SERVICE_NAME}.service${RESET} (Consensus Client)"
    echo -e "  • ${CYAN}${OG_GETH_SERVICE_NAME:-0g-geth}.service${RESET} or ${CYAN}${OG_RETH_SERVICE_NAME:-0g-reth}.service${RESET} (Execution Client)"
    
    echo -e "\n${RED}Existing Services to be Replaced:${RESET}"
    echo -e "  • ${CYAN}0gchaind${RESET}"
    echo -e "  • ${CYAN}0g-geth${RESET} / ${CYAN}0g-reth${RESET} / ${CYAN}reth${RESET}"
    echo -e "  • ${CYAN}0ggeth${RESET}"
    
    echo -e "\n${GREEN}Port Configuration:${RESET}"
    echo -e "Ports will be adjusted based on your input (example if you enter 28):"
    echo -e "  • ${CYAN}28657${RESET} (RPC) <-- 26657"
    echo -e "  • ${CYAN}28656${RESET} (P2P) <-- 26656"
    echo -e "  • ${CYAN}28545${RESET} (EVM-RPC) <-- 8545"
    echo -e "  • ${CYAN}28546${RESET} (WebSocket) <-- 8546"
    
    echo -e "\n${GREEN}Directories:${RESET}"
    echo -e "  • ${CYAN}$HOME/.0gchaind${RESET}"

    echo -e "\n${YELLOW}3. REQUIREMENTS:${RESET}"
    echo "- CPU: 8+ cores, RAM: 64+ GB, Storage: 1TB+ NVMe SSD"
    echo "- Ubuntu 22.04/24.04 recommended"

    echo -e "\n${YELLOW}4. VALIDATOR RESPONSIBILITIES:${RESET}"
    echo "- As a validator, you'll need to:"
    echo "  - Maintain good uptime (recommended 99%+)"
    echo "  - Keep your node software updated"
    echo "  - Regularly backup your keys and data"
    echo "- The network has slashing mechanisms to:"
    echo "  - Encourage validator reliability"
    echo "  - Prevent malicious behavior"

    echo -e "\n${GREEN}By continuing you agree to these terms.${RESET}"
    read -p $'\n\e[33mDo you want to proceed with installation? (yes/no): \e[0m' confirm
    
    if [[ "${confirm,,}" != "yes" ]]; then
        echo -e "${RED}Installation cancelled by user.${RESET}"
        menu
        return
    fi

    echo -e "\n${GREEN}Starting installation...${RESET}"
    echo -e "${YELLOW}This may take 1-5 minutes. Please don't interrupt the process.${RESET}"
    sleep 2

    run_repository_script resources/0g_validator_node_aristotle_install.sh
    menu
}

function manage_validator_node() {
    echo "Choose an option:"
    echo "1. Update Validator Node Version"
    echo "2. Back"
    read -p "Enter your choice (1/2): " choice

    case $choice in
        1)
            run_repository_script resources/0g_validator_node_update_manual.sh
            menu
            ;;
        2)
            menu
            ;;
        *)
            echo "Invalid choice. Please select a valid option."
            ;;
    esac
}

# Function to migrate to Cosmovisor


function apply_snapshot() {
     run_repository_script resources/apply_snapshot.sh
     menu
}

function install_0gchain_app() {
    run_repository_script resources/0gchain_app_install.sh
    menu
}

function create_validator() {
    # Only check; install is optional and prompted later if needed for auto path
    ensure_evm_cli_tools check || true
    # Detect legacy key persistence by name only; never read the value
    warn_legacy_private_key_file
    echo -e "${CYAN}Create 0G Validator (Mainnet / Aristotle)${RESET}"
    echo -e "${YELLOW}Requirements:${RESET} Ensure 0gchaind and 0g-geth are fully synced, and your EVM wallet holds at least 500 OG plus gas."

    # Defaults (overridable via ENV)
    BIN_0GCHAIND="${BIN_0GCHAIND:-0gchaind}"
    OG_HOME="${OG_HOME:-$HOME/.0gchaind/0g-home/0gchaind-home}"
    OG_GENESIS_PATH="${OG_GENESIS_PATH:-$OG_HOME/config/genesis.json}"
    OG_EVM_RPC="${OG_EVM_RPC:-https://evmrpc.0g.ai}"
    STAKING_ADDRESS="${STAKING_ADDRESS:-0xea224dBB52F57752044c0C86aD50930091F561B9}"
    DEPOSIT_MSG_AMOUNT="${DEPOSIT_MSG_AMOUNT:-500000000000}"
    WITHDRAW_GWEI_DEFAULT="${WITHDRAW_GWEI_DEFAULT:-1}"

    # Inputs
    read -p "Enter validator name (moniker): " OG_MONIKER
    read -p "Enter identity (Keybase, optional): " IDENTITY
    read -p "Enter website URL (optional): " WEBSITE
    read -p "Enter security contact email: " EMAIL
    read -p "Enter details (≤200 chars): " DETAILS

    read -p "Commission rate in % (e.g., 5 for 5%): " COMM_PCT
    COMM_PCT=${COMM_PCT:-5}
    if ! COMM_PPM=$(staking_rewards_percent_to_ppm "${COMM_PCT:-0}"); then
        echo -e "${RED}Invalid commission (0–100).${RESET}"; menu; return 1
    fi

    read -p "Withdrawal fee in Gwei [default ${WITHDRAW_GWEI_DEFAULT}]: " WITHDRAW_GWEI
    WITHDRAW_GWEI=${WITHDRAW_GWEI:-$WITHDRAW_GWEI_DEFAULT}

    read -p "Custom EVM RPC? [Enter to use ${OG_EVM_RPC}]: " RPC_INPUT
    if [ -n "${RPC_INPUT}" ]; then OG_EVM_RPC="$RPC_INPUT"; fi

    echo -e "\n${YELLOW}Summary:${RESET}"
    echo "  Moniker:            $OG_MONIKER"
    echo "  Commission (ppm):   $COMM_PPM  (${COMM_PCT}%)"
    echo "  Withdrawal fee:     ${WITHDRAW_GWEI} Gwei"
    echo "  EVM RPC:            $OG_EVM_RPC"
    echo "  Staking Contract:   $STAKING_ADDRESS"
    echo "  Payable on tx:      500 OG"
    read -p "Proceed? (y/n, b=back): " CONFIRM
    case "${CONFIRM,,}" in
        y|yes) ;;
        b|back) echo -e "${YELLOW}Returning to menu...${RESET}"; menu; return 0 ;;
        *) echo -e "${RED}Cancelled.${RESET}"; menu; return 1 ;;
    esac

    # 1) Generate deposit message (pubkey + signature)
    echo -e "${CYAN}Generating deposit message (pubkey + signature)...${RESET}"
    TMP_OUT="$(mktemp)"
    $BIN_0GCHAIND deposit create-delegation-validator \
        "$STAKING_ADDRESS" \
        "$DEPOSIT_MSG_AMOUNT" \
        "$OG_GENESIS_PATH" \
        --home "$OG_HOME" \
        --chaincfg.chain-spec=mainnet \
        --override-rpc-url \
        --rpc-dial-url "$OG_EVM_RPC" | tee "$TMP_OUT"
    RC=$?
    if [ $RC -ne 0 ]; then
        echo -e "${RED}Failed to create deposit message.${RESET}"; rm -f "$TMP_OUT"; menu; return 1
    fi

    PUBKEY=$(grep -Eo 'pubkey: 0x[0-9a-fA-F]+' "$TMP_OUT" | awk '{print $2}')
    SIGNATURE=$(grep -Eo 'signature: 0x[0-9a-fA-F]+' "$TMP_OUT" | awk '{print $2}')
    rm -f "$TMP_OUT"
    if [ -z "$PUBKEY" ] || [ -z "$SIGNATURE" ]; then
        echo -e "${RED}Could not parse pubkey/signature.${RESET}"; menu; return 1
    fi

    # 2) Validate signature
    echo -e "${CYAN}Validating deposit message...${RESET}"
    $BIN_0GCHAIND deposit validate-delegation \
        "$PUBKEY" \
        "$STAKING_ADDRESS" \
        "$DEPOSIT_MSG_AMOUNT" \
        "$SIGNATURE" \
        "$OG_GENESIS_PATH" \
        --home "$OG_HOME" \
        --chaincfg.chain-spec=mainnet \
        --override-rpc-url \
        --rpc-dial-url "$OG_EVM_RPC"

    # 3) Execute init tx through Foundry's native interactive signer.
    echo -e "${CYAN}Initializing validator on Staking Contract...${RESET}"
    if ! command -v cast >/dev/null 2>&1; then
        echo -e "${YELLOW}'cast' is not available for interactive submission.${RESET}"
        read -p "Install Foundry to enable interactive submission? (y/n, b=back): " _ans
        case "${_ans,,}" in
          y|yes) ensure_evm_cli_tools prompt || true ;;
          b|back) echo -e "${YELLOW}Returning to menu...${RESET}"; menu; return 0 ;;
          *) : ;;
        esac
    fi

    if command -v cast >/dev/null 2>&1; then
        DESC_TUPLE=$(printf '("%s","%s","%s","%s","%s")' "$OG_MONIKER" "$IDENTITY" "$WEBSITE" "$EMAIL" "$DETAILS")
        echo -e "${YELLOW}Foundry will prompt for the signer. Valley will not receive or persist the wallet private key.${RESET}"
        cast send "$STAKING_ADDRESS" \
            'createAndInitializeValidatorIfNecessary((string,string,string,string,string),uint32,uint96,bytes,bytes)' \
            "$DESC_TUPLE" \
            "$COMM_PPM" \
            "$WITHDRAW_GWEI" \
            "$PUBKEY" \
            "$SIGNATURE" \
            --value 500ether \
            --rpc-url "$OG_EVM_RPC" \
            --interactive
        echo -e "${GREEN}Submitted. Track on https://chainscan.0g.ai/${RESET}"
    else
        echo -e "${YELLOW}Manual path (ChainScan UI):${RESET}"
        echo "  1) Open: https://chainscan.0g.ai/address/$STAKING_ADDRESS (Contracts -> Write as Proxy)"
        echo "  2) Call: createAndInitializeValidatorIfNecessary"
        echo "     - description.moniker         = $OG_MONIKER"
        echo "     - description.identity        = $IDENTITY"
        echo "     - description.website         = $WEBSITE"
        echo "     - description.securityContact = $EMAIL"
        echo "     - description.details         = $DETAILS"
        echo "     - commissionRate (ppm)        = $COMM_PPM"
        echo "     - withdrawalFeeInGwei         = $WITHDRAW_GWEI"
        echo "     - pubkey                      = $PUBKEY"
        echo "     - signature                   = $SIGNATURE"
        echo "  3) Set payable amount = 500 OG, then submit."
    fi

    echo -e "\n${YELLOW}Validator may appear active after ~30–60 minutes on the explorer:${RESET}"
    echo "  https://explorer.0g.ai/mainnet/validators"
    echo -e "${YELLOW}Press Enter to return to menu...${RESET}"
    read -r
    menu
}

# Delegate to a validator (0G Mainnet / Aristotle)
function delegate_to_validator() {
    set -euo pipefail

    # Tools: Foundry (cast) optional for interactive signing; Valley never handles the signer key
    ensure_evm_cli_tools check || true
    warn_legacy_private_key_file

    # 'bc' is not strictly required for delegation, but useful to have
    if ! command -v bc >/dev/null 2>&1; then
      echo -e "${YELLOW}Installing 'bc' (optional, useful for math) ...${RESET}"
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y && sudo apt-get install -y bc || true
      fi
    fi

    echo -e "${CYAN}Delegate 0G to Validator${RESET}"
    echo -e "${YELLOW}Requirements:${RESET} EVM wallet with 0G for stake + gas. For interactive submission, 'cast' must be available; Foundry prompts for the signer itself."

    # Defaults (override via ENV)
    OG_EVM_RPC="${OG_EVM_RPC:-https://evmrpc.0g.ai}"
    STAKING_ADDRESS="${STAKING_ADDRESS:-0xea224dBB52F57752044c0C86aD50930091F561B9}"
    GV_VALIDATOR_ADDR="${GV_VALIDATOR_ADDR:-0x108e619dA0cdbA8A301A53948A4aCc23A3d79377}"
    GV_VALIDATOR_PUBKEY="${GV_VALIDATOR_PUBKEY:-0xb589c0c26210a065a4c4aee068346301490efad5bfaa0578f186c6e41cc4018004f08a411ef0f056468174c260307b7e}"

    echo "Select how to specify the validator:"
    echo "  1) Enter validator contract address (0x...)"
    echo "  2) Enter validator PUBKEY (48-byte) and resolve via Staking.getValidator(bytes)"
    echo "  3) Use Grand Valley defaults from ENV (GV_VALIDATOR_ADDR / GV_VALIDATOR_PUBKEY)"
    read -p "Choice [1/2/3, b=back]: " MODE
    if [[ "${MODE,,}" == "b" || "${MODE,,}" == "back" ]]; then menu; return; fi

    VALIDATOR_ADDR=""
    case "${MODE:-3}" in
      1)
        read -p "Validator contract address (0x...): " VALIDATOR_ADDR
        ;;
      2)
        read -p "Validator PUBKEY (0x... 48-byte): " VAL_PUBKEY
        if ! command -v cast >/dev/null 2>&1; then
          echo -e "${YELLOW}'cast' is required to resolve validator address from PUBKEY.${RESET}"
          read -p "Install Foundry now? (y/n, b=back): " _ans
          case "${_ans,,}" in
            y|yes) ensure_evm_cli_tools prompt || true ;;
            b|back) menu; return 0 ;;
            *) echo -e "${RED}Cannot resolve without 'cast'.${RESET}"; return 1 ;;
          esac
        fi
        command -v cast >/dev/null 2>&1 || { echo -e "${RED}Cast still unavailable.${RESET}"; return 1; }
        VALIDATOR_ADDR=$(cast call "$STAKING_ADDRESS" 'getValidator(bytes)(address)' "$VAL_PUBKEY" --rpc-url "$OG_EVM_RPC" | staking_rewards_first_token)
        [[ -z "$VALIDATOR_ADDR" || "$VALIDATOR_ADDR" == "0x0000000000000000000000000000000000000000" ]] && { echo -e "${RED}Validator not found for the provided PUBKEY.${RESET}"; return 1; }
        ;;
      3|*)
        if [ -n "$GV_VALIDATOR_ADDR" ]; then
          VALIDATOR_ADDR="$GV_VALIDATOR_ADDR"
        elif [ -n "$GV_VALIDATOR_PUBKEY" ]; then
          if ! command -v cast >/dev/null 2>&1; then
            echo -e "${YELLOW}'cast' is required to resolve GV_VALIDATOR_PUBKEY.${RESET}"
            read -p "Install Foundry now? (y/n, b=back): " _ans
            case "${_ans,,}" in
              y|yes) ensure_evm_cli_tools prompt || true ;;
              b|back) menu; return 0 ;;
              *) echo -e "${RED}Cannot resolve without 'cast'.${RESET}"; return 1 ;;
            esac
          fi
          command -v cast >/dev/null 2>&1 || { echo -e "${RED}Cast still unavailable.${RESET}"; return 1; }
          VALIDATOR_ADDR=$(cast call "$STAKING_ADDRESS" 'getValidator(bytes)(address)' "$GV_VALIDATOR_PUBKEY" --rpc-url "$OG_EVM_RPC" | staking_rewards_first_token)
          [[ -z "$VALIDATOR_ADDR" || "$VALIDATOR_ADDR" == "0x0000000000000000000000000000000000000000" ]] && { echo -e "${RED}Validator not found for GV_VALIDATOR_PUBKEY.${RESET}"; return 1; }
        else
          echo -e "${RED}GV_VALIDATOR_ADDR / GV_VALIDATOR_PUBKEY not set.${RESET}"
          return 1
        fi
        ;;
    esac

    read -p "Enter delegation amount in OG (decimals allowed, e.g., 123.45) [b=back]: " AMOUNT_OG
    if [[ "${AMOUNT_OG,,}" == "b" || "${AMOUNT_OG,,}" == "back" ]]; then menu; return; fi
    [[ -z "${AMOUNT_OG:-}" || ! "$AMOUNT_OG" =~ ^[0-9]+([.][0-9]+)?$ ]] && { echo -e "${RED}Invalid amount.${RESET}"; return 1; }

    read -p "Your EVM address (delegator, 0x...): " DELEGATOR_ADDR

    read -p "Custom EVM RPC? [Enter to use ${OG_EVM_RPC}, b=back]: " RPC_INPUT
    if [[ "${RPC_INPUT,,}" == "b" || "${RPC_INPUT,,}" == "back" ]]; then menu; return; fi
    if [ -n "${RPC_INPUT}" ]; then OG_EVM_RPC="$RPC_INPUT"; fi

    echo -e "\n${YELLOW}Summary:${RESET}"
    echo "  Validator:  $VALIDATOR_ADDR"
    echo "  Delegator:  $DELEGATOR_ADDR"
    echo "  Amount:     $AMOUNT_OG OG"
    echo "  RPC:        $OG_EVM_RPC"
    read -p "Proceed with delegation? (y/n, b=back): " OK
    case "${OK,,}" in
      y|yes) ;;
      b|back) echo -e "${YELLOW}Returning to menu...${RESET}"; menu; return 0 ;;
      *) echo -e "${RED}Cancelled.${RESET}"; return 1 ;;
    esac

    if command -v cast >/dev/null 2>&1 ; then
      echo -e "${CYAN}Sending delegation transaction via 'cast'...${RESET}"
      TX_OUT=$(
        cast send "$VALIDATOR_ADDR" \
          'delegate(address)' "$DELEGATOR_ADDR" \
          --value "${AMOUNT_OG}ether" \
          --rpc-url "$OG_EVM_RPC" \
          --interactive 2>&1 | tee /dev/tty
      )
      # Extract transaction hash (JSON or plain)
      TX_HASH=$(echo "$TX_OUT" | sed -n 's/.*"transactionHash"[[:space:]]*:[[:space:]]*"\(0x[0-9a-fA-F]\{64\}\)".*/\1/p' | head -n1)
      if [ -z "$TX_HASH" ]; then
        TX_HASH=$(echo "$TX_OUT" | sed -n 's/.*transactionHash[[:space:]]*\(0x[0-9a-fA-F]\{64\}\).*/\1/p' | head -n1)
      fi
      if [ -z "$TX_HASH" ]; then
        TX_HASH=$(echo "$TX_OUT" | grep -Eo '0x[0-9a-fA-F]{64}' | head -n1)
      fi

      if [ -n "$TX_HASH" ]; then
        echo -e "${GREEN}Delegation submitted. Track on Chainscan:${RESET} https://chainscan.0g.ai/tx/$TX_HASH"
      else
        echo -e "${YELLOW}Delegation submitted (tx hash not detected). Track contract:${RESET} https://chainscan.0g.ai/address/$VALIDATOR_ADDR"
      fi
    else
      echo -e "${YELLOW}Manual path (Chainscan UI):${RESET}"
      echo "  1) Open https://chainscan.0g.ai/address/$VALIDATOR_ADDR"
      echo "  2) Contract -> Write -> select 'delegate(address)'"
      echo "  3) Set 'delegator' = $DELEGATOR_ADDR"
      echo "  4) Set payable value = $AMOUNT_OG OG (native), connect your 0G Mainnet wallet, then submit."
    fi

    echo -e "${YELLOW}Useful checks:${RESET}"
    echo "  # Delegation info (returns delegator, shares):"
    echo "  cast call $VALIDATOR_ADDR 'getDelegation(address)(address,uint256)' $DELEGATOR_ADDR --rpc-url $OG_EVM_RPC"
    echo "  # Total tokens and shares on the validator:"
    echo "  cast call $VALIDATOR_ADDR 'tokens()(uint256)' --rpc-url $OG_EVM_RPC"
    echo "  cast call $VALIDATOR_ADDR 'delegatorShares()(uint256)' --rpc-url $OG_EVM_RPC"

    echo -e "\n${YELLOW}Press Enter to go back to main menu...${RESET}"
    read -r
    menu
}

# Undelegate from a validator (0G Mainnet / Aristotle)
function undelegate_from_validator() {
  set -euo pipefail

  # Tools for interactive signing; Valley never handles the signer key
  ensure_evm_cli_tools prompt || true
  warn_legacy_private_key_file

  # Ensure 'bc' for big-int math
  if ! command -v bc >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing 'bc' (required for share calculations) ...${RESET}"
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y && sudo apt-get install -y bc || true
    fi
    command -v bc >/dev/null 2>&1 || { echo -e "${RED}'bc' is required for the OG→shares calculation.${RESET}"; return 1; }
  fi

  echo -e "${CYAN}Undelegate from Validator${RESET}"
  echo -e "${YELLOW}Requirements:${RESET} A small amount of 0G for gas and the validator's withdrawal fee (in gwei). For interactive submission, 'cast' must be available; Foundry prompts for the signer itself."

  # ===== Defaults (override via ENV) =====
  OG_EVM_RPC="${OG_EVM_RPC:-https://evmrpc.0g.ai}"
  STAKING_ADDRESS="${STAKING_ADDRESS:-0xea224dBB52F57752044c0C86aD50930091F561B9}"
  GV_VALIDATOR_ADDR="${GV_VALIDATOR_ADDR:-0x108e619dA0cdbA8A301A53948A4aCc23A3d79377}"
  GV_VALIDATOR_PUBKEY="${GV_VALIDATOR_PUBKEY:-0xb589c0c26210a065a4c4aee068346301490efad5bfaa0578f186c6e41cc4018004f08a411ef0f056468174c260307b7e}"

  # ===== Choose how to specify the validator =====
  echo "Select how to specify the validator:"
  echo "  1) Enter validator contract address (0x...)"
  echo "  2) Enter validator PUBKEY (48-byte) and resolve via Staking.getValidator(bytes)"
  echo "  3) Use Grand Valley defaults from ENV (GV_VALIDATOR_ADDR / GV_VALIDATOR_PUBKEY)"
  read -rp "Choice [1/2/3, b=back]: " MODE
  if [[ "${MODE,,}" == "b" || "${MODE,,}" == "back" ]]; then menu; return; fi

  VALIDATOR_ADDR=""
  case "${MODE:-3}" in
    1)
      read -rp "Validator contract address (0x...): " VALIDATOR_ADDR
      ;;
    2)
      read -rp "Validator PUBKEY (0x... 48-byte): " VAL_PUBKEY
      if command -v cast >/dev/null 2>&1; then
        VALIDATOR_ADDR=$(cast call "$STAKING_ADDRESS" 'getValidator(bytes)(address)' "$VAL_PUBKEY" --rpc-url "$OG_EVM_RPC" | staking_rewards_first_token)
      else
        echo -e "${RED}Resolving from pubkey requires 'cast'.${RESET}"; return 1
      fi
      ;;
    3|*)
      if [ -n "$GV_VALIDATOR_ADDR" ]; then
        VALIDATOR_ADDR="$GV_VALIDATOR_ADDR"
      elif [ -n "$GV_VALIDATOR_PUBKEY" ] && command -v cast >/dev/null 2>&1; then
        VALIDATOR_ADDR=$(cast call "$STAKING_ADDRESS" 'getValidator(bytes)(address)' "$GV_VALIDATOR_PUBKEY" --rpc-url "$OG_EVM_RPC" | staking_rewards_first_token)
      fi
      ;;
  esac

  if [[ -z "$VALIDATOR_ADDR" || "$VALIDATOR_ADDR" == "0x0000000000000000000000000000000000000000" ]]; then
    echo -e "${RED}Validator address not resolved. Provide a contract address or ensure 'cast' is available for PUBKEY resolution.${RESET}"
    return 1
  fi

  # ===== Delegator address =====
  read -rp "Your EVM address (delegator, 0x...): " DELEGATOR_ADDR

  # ===== Optional: custom RPC =====
  read -rp "Custom EVM RPC? [Enter to use ${OG_EVM_RPC}, b=back]: " RPC_INPUT
  if [[ "${RPC_INPUT,,}" == "b" || "${RPC_INPUT,,}" == "back" ]]; then menu; return; fi
  if [ -n "${RPC_INPUT}" ]; then OG_EVM_RPC="$RPC_INPUT"; fi

  # ===== Input mode: OG amount -> shares; or raw shares =====
  echo "Select undelegation input:"
  echo "  1) Enter target amount in OG (recommended)"
  echo "  2) Enter raw shares (advanced)"
  read -rp "Choice [1/2, b=back]: " AMODE
  if [[ "${AMODE,,}" == "b" || "${AMODE,,}" == "back" ]]; then menu; return; fi

  SHARES=""
  AMOUNT_OG=""
  if [[ "${AMODE:-1}" == "2" ]]; then
    read -rp "Shares to undelegate (uint) [b=back]: " SHARES
    if [[ "${SHARES,,}" == "b" || "${SHARES,,}" == "back" ]]; then menu; return; fi
    [[ -z "$SHARES" || ! "$SHARES" =~ ^[0-9]+$ ]] && { echo -e "${RED}Invalid shares.${RESET}"; return 1; }
  else
    read -rp "Target amount to withdraw (in OG, decimals allowed, e.g., 12.34) [b=back]: " AMOUNT_OG
    if [[ "${AMOUNT_OG,,}" == "b" || "${AMOUNT_OG,,}" == "back" ]]; then menu; return; fi
    [[ -z "${AMOUNT_OG:-}" || ! "$AMOUNT_OG" =~ ^[0-9]+([.][0-9]+)?$ ]] && { echo -e "${RED}Invalid amount.${RESET}"; return 1; }
  fi

  # ===== Read pool state & compute shares if needed =====
  if [ -z "$SHARES" ]; then
    if ! command -v cast >/dev/null 2>&1; then
      echo -e "${RED}On-chain reads require 'cast'. Install it or use raw shares (option 2).${RESET}"
      return 1
    fi

    TOTAL_TOKENS=$(cast call "$VALIDATOR_ADDR" 'tokens()(uint256)' --rpc-url "$OG_EVM_RPC" | staking_rewards_first_token)
    TOTAL_SHARES=$(cast call "$VALIDATOR_ADDR" 'delegatorShares()(uint256)' --rpc-url "$OG_EVM_RPC" | staking_rewards_first_token)

    if [[ -z "$TOTAL_TOKENS" || "$TOTAL_TOKENS" == "0" || -z "$TOTAL_SHARES" || "$TOTAL_SHARES" == "0" ]]; then
      echo -e "${RED}Pool state invalid (zero tokens or shares).${RESET}"; return 1
    fi

    # getDelegation returns (address, uint). Take the last line as shares.
    mapfile -t _DELEG_OUT < <(cast call "$VALIDATOR_ADDR" 'getDelegation(address)(address,uint256)' "$DELEGATOR_ADDR" --rpc-url "$OG_EVM_RPC")
    MY_SHARES=$(echo "${_DELEG_OUT[-1]}" | awk '{print $1}' | tr -d '[:space:]')

    if [[ -z "$MY_SHARES" || "$MY_SHARES" == "0" ]]; then
      echo -e "${RED}No active delegation found for this address.${RESET}"; return 1
    fi

    AMOUNT_WEI=$(cast to-wei "$AMOUNT_OG" ether | staking_rewards_first_token)
    if [[ -z "$AMOUNT_WEI" || ! "$AMOUNT_WEI" =~ ^[0-9]+$ ]]; then
      echo -e "${RED}Failed to convert amount to wei.${RESET}"; return 1
    fi

    # sharesNeeded = ceil(amountWei * totalShares / totalTokens)
    SHARES=$(echo "($AMOUNT_WEI * $TOTAL_SHARES + $TOTAL_TOKENS - 1) / $TOTAL_TOKENS" | bc)
    if staking_rewards_uint_lte_zero "$SHARES"; then
      echo -e "${RED}Computed shares <= 0. Choose a larger amount.${RESET}"; return 1
    fi
    if staking_rewards_uint_gt "$SHARES" "$MY_SHARES"; then
      echo -e "${RED}Computed shares exceed your current shares ($MY_SHARES). Lower the amount.${RESET}"; return 1
    fi
  fi

  # ===== Withdrawal recipient (defaults to delegator) =====
  read -rp "Withdrawal recipient (default: $DELEGATOR_ADDR, b=back): " WITHDRAW_ADDR
  if [[ "${WITHDRAW_ADDR,,}" == "b" || "${WITHDRAW_ADDR,,}" == "back" ]]; then menu; return; fi
  WITHDRAW_ADDR=${WITHDRAW_ADDR:-$DELEGATOR_ADDR}

  # ===== Withdrawal fee (msg.value) =====
  if command -v cast >/dev/null 2>&1; then
    FEE_GWEI=$(cast call "$VALIDATOR_ADDR" 'withdrawalFeeInGwei()(uint96)' --rpc-url "$OG_EVM_RPC" | staking_rewards_first_token)
    FEE_WEI=$(cast to-wei "$FEE_GWEI" gwei)
  else
    read -rp "Validator withdrawal fee in Gwei (cannot query without 'cast'): " FEE_GWEI
    FEE_WEI=$(printf "%.0f" "$(awk "BEGIN{print $FEE_GWEI * 1000000000}")")
  fi

  # ===== Confirm =====
  echo -e "\n${YELLOW}Summary:${RESET}"
  echo "  Validator:         $VALIDATOR_ADDR"
  echo "  Delegator:         $DELEGATOR_ADDR"
  echo "  Withdrawal to:     $WITHDRAW_ADDR"
  echo "  Shares to remove:  $SHARES"
  echo "  Withdrawal fee:    ${FEE_GWEI:-unknown} gwei (${FEE_WEI} wei)"
  echo "  RPC:               $OG_EVM_RPC"
  read -rp "Proceed with undelegation? (y/n, b=back): " OK
  case "${OK,,}" in
    y|yes) ;;
    b|back) echo -e "${YELLOW}Returning to menu...${RESET}"; menu; return 0 ;;
    *) echo -e "${RED}Cancelled.${RESET}"; return 1 ;;
  esac

  # ===== Send TX or print manual steps =====
  if command -v cast >/dev/null 2>&1 ; then
    echo -e "${CYAN}Sending undelegation transaction via 'cast'...${RESET}"
    TX_OUT=$(
      cast send "$VALIDATOR_ADDR" \
        'undelegate(address,uint256)' "$WITHDRAW_ADDR" "$SHARES" \
        --value "$FEE_WEI" \
        --rpc-url "$OG_EVM_RPC" \
        --interactive 2>&1 | tee /dev/tty
    )

    # Extract transaction hash (JSON or plain)
    TX_HASH=$(echo "$TX_OUT" | sed -n 's/.*"transactionHash"[[:space:]]*:[[:space:]]*"\(0x[0-9a-fA-F]\{64\}\)".*/\1/p' | head -n1)
    if [ -z "$TX_HASH" ]; then
      TX_HASH=$(echo "$TX_OUT" | sed -n 's/.*transactionHash[[:space:]]*\(0x[0-9a-fA-F]\{64\}\).*/\1/p' | head -n1)
    fi
    if [ -z "$TX_HASH" ]; then
      TX_HASH=$(echo "$TX_OUT" | grep -Eo '0x[0-9a-fA-F]{64}' | head -n1)
    fi

    if [ -n "$TX_HASH" ]; then
      echo -e "${GREEN}Undelegation submitted. Track on Chainscan:${RESET} https://chainscan.0g.ai/tx/$TX_HASH"
    else
      echo -e "${YELLOW}Undelegation submitted (tx hash not detected). Track contract:${RESET} https://chainscan.0g.ai/address/$VALIDATOR_ADDR"
    fi
  else
    echo -e "${YELLOW}Manual path (Chainscan UI):${RESET}"
    echo "  1) Open https://chainscan.0g.ai/address/$VALIDATOR_ADDR"
    echo "  2) Contract → Write → select 'undelegate(address,uint256)'"
    echo "  3) Set:"
    echo "       withdrawalAddress = $WITHDRAW_ADDR"
    echo "       shares            = $SHARES"
    echo "  4) Set payable value = ${FEE_GWEI:-<fee in gwei>} gwei (i.e., ${FEE_WEI} wei)."
    echo "  5) Connect your 0G Mainnet wallet and submit."
  fi

    echo -e "\n${YELLOW}Press Enter to go back to main menu...${RESET}"
    read -r
    menu
}

function staking_rewards_safe_call() {
  local contract="$1"
  local signature="$2"
  shift 2
  local out status

  set +e
  out=$(cast call "$contract" "$signature" "$@" --rpc-url "$OG_EVM_RPC" 2>/dev/null)
  status=$?
  set -e

  if [ $status -ne 0 ] || [ -z "$out" ]; then
    return 1
  fi

  echo "$out" | tail -n1 | awk '{print $1}' | tr -d '[:space:]'
}

function staking_rewards_first_token() {
  tail -n1 | awk '{print $1}' | tr -d '[:space:]'
}

function staking_rewards_uint_lte_zero() {
  local value="${1:-}"

  if [[ -z "$value" || ! "$value" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  [[ "$(echo "$value <= 0" | bc)" == "1" ]]
}

function staking_rewards_uint_gt() {
  local left="${1:-}"
  local right="${2:-}"

  if [[ ! "$left" =~ ^[0-9]+$ || ! "$right" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  [[ "$(echo "$left > $right" | bc)" == "1" ]]
}

function staking_rewards_display_og() {
  local wei="${1:-}"

  if [[ -z "$wei" || "$wei" == "N/A" || ! "$wei" =~ ^[0-9]+$ ]]; then
    echo "N/A"
    return 0
  fi

  if command -v cast >/dev/null 2>&1; then
    cast from-wei "$wei" ether 2>/dev/null || echo "N/A"
  elif command -v bc >/dev/null 2>&1; then
    echo "scale=18; $wei / 1000000000000000000" | bc
  else
    echo "$wei wei"
  fi
}

function staking_rewards_hex_to_dec() {
  local value="${1:-}"

  value="${value#0x}"
  [[ "$value" =~ ^[0-9a-fA-F]+$ ]] || return 1
  echo $((16#$value))
}

function staking_rewards_block_timestamp() {
  local block="$1"
  local raw timestamp

  set +e
  raw=$(cast block "$block" --json --rpc-url "$OG_EVM_RPC" 2>/dev/null)
  set -e

  timestamp=$(echo "$raw" | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p' | head -n1)
  [ -n "$timestamp" ] || return 1
  staking_rewards_hex_to_dec "$timestamp"
}

function staking_rewards_format_duration() {
  local seconds="${1:-}"
  local days hours minutes

  [[ "$seconds" =~ ^[0-9]+$ ]] || { echo "N/A"; return 0; }
  if [ "$seconds" -le 0 ]; then
    echo "ready now"
    return 0
  fi

  days=$((seconds / 86400))
  seconds=$((seconds % 86400))
  hours=$((seconds / 3600))
  seconds=$((seconds % 3600))
  minutes=$((seconds / 60))
  seconds=$((seconds % 60))

  if [ "$days" -gt 0 ]; then
    printf "%dd %dh %dm" "$days" "$hours" "$minutes"
  elif [ "$hours" -gt 0 ]; then
    printf "%dh %dm" "$hours" "$minutes"
  elif [ "$minutes" -gt 0 ]; then
    printf "%dm %ds" "$minutes" "$seconds"
  else
    printf "%ds" "$seconds"
  fi
}

function staking_rewards_block_time_sample() {
  local current_block="$1"
  local sample_blocks="${2:-200}"
  local past_block current_ts past_ts elapsed

  [[ "$current_block" =~ ^[0-9]+$ ]] || return 1
  if [ "$current_block" -le "$sample_blocks" ]; then
    sample_blocks=$((current_block - 1))
  fi
  [ "$sample_blocks" -gt 0 ] || return 1

  past_block=$((current_block - sample_blocks))
  current_ts=$(staking_rewards_block_timestamp "$current_block") || return 1
  past_ts=$(staking_rewards_block_timestamp "$past_block") || return 1
  elapsed=$((current_ts - past_ts))

  [ "$elapsed" -gt 0 ] || return 1
  printf "%s %s" "$sample_blocks" "$elapsed"
}

function staking_rewards_decimal_div() {
  local value="${1:-}"
  local divisor="${2:-1}"
  local scale="${3:-4}"

  if [[ -z "$value" || "$value" == "N/A" || ! "$value" =~ ^[0-9]+$ ]]; then
    echo "N/A"
    return 0
  fi

  echo "scale=$scale; $value / $divisor" | bc
}

function staking_rewards_bigint_lt() {
  local left="${1:-0}"
  local right="${2:-0}"

  [[ "$left" =~ ^[0-9]+$ && "$right" =~ ^[0-9]+$ ]] || return 1
  [ "$(echo "$left < $right" | bc)" = "1" ]
}

function staking_rewards_extract_tx_hash() {
  local tx_out="$1"
  local tx_hash

  tx_hash=$(echo "$tx_out" | sed -n 's/.*"transactionHash"[[:space:]]*:[[:space:]]*"\(0x[0-9a-fA-F]\{64\}\)".*/\1/p' | head -n1)
  if [ -z "$tx_hash" ]; then
    tx_hash=$(echo "$tx_out" | sed -n 's/.*transactionHash[[:space:]]*\(0x[0-9a-fA-F]\{64\}\).*/\1/p' | head -n1)
  fi
  if [ -z "$tx_hash" ]; then
    tx_hash=$(echo "$tx_out" | grep -Eo '0x[0-9a-fA-F]{64}' | head -n1)
  fi

  echo "$tx_hash"
}

function staking_rewards_pause() {
  echo -e "\n${YELLOW}Press Enter to return to staking rewards submenu...${RESET}"
  read -r
}

function staking_rewards_percent_to_ppm() {
  local percent="$1"
  local whole fraction

  if [[ ! "$percent" =~ ^([0-9]{1,2}([.][0-9]{1,4})?|100([.]0{1,4})?)$ ]]; then
    return 1
  fi

  whole="${percent%%.*}"
  if [[ "$percent" == *.* ]]; then
    fraction="${percent#*.}"
  else
    fraction=""
  fi
  fraction="${fraction}0000"
  fraction="${fraction:0:4}"

  printf '%d\n' "$((10#$whole * 10000 + 10#$fraction))"
}

function staking_rewards_operator_warning() {
  local operator_addr="$1"
  echo -e "${YELLOW}Operator-only action: when Foundry prompts for the signer, use the operator wallet ${operator_addr}.${RESET}"
  echo -e "${YELLOW}Valley does not read, persist, or pass that wallet private key.${RESET}"
}

function staking_rewards_send_no_value() {
  local validator_addr="$1"
  local signature="$2"
  local success_label="$3"
  shift 3
  local tx_out tx_hash

  echo -e "${CYAN}Sending transaction via 'cast' (Foundry will prompt for the signer securely)...${RESET}"
  TX_OUT=$(
    cast send "$validator_addr" \
      "$signature" "$@" \
      --rpc-url "$OG_EVM_RPC" \
      --interactive 2>&1 | tee /dev/tty
  )
  tx_out="$TX_OUT"
  tx_hash=$(staking_rewards_extract_tx_hash "$tx_out")

  if [ -n "$tx_hash" ]; then
    echo -e "${GREEN}$success_label submitted. Track on Chainscan:${RESET} https://chainscan.0g.ai/tx/$tx_hash"
  else
    echo -e "${YELLOW}$success_label submitted (tx hash not detected). Track contract:${RESET} https://chainscan.0g.ai/address/$validator_addr"
  fi
}

function manage_staking_rewards() {
  set -euo pipefail

  ensure_evm_cli_tools prompt || true
  warn_legacy_private_key_file

  if ! command -v cast >/dev/null 2>&1; then
    echo -e "${RED}'cast' is required for staking rewards management.${RESET}"
    echo -e "${YELLOW}Install Foundry, then reopen this menu.${RESET}"
    read -r
    menu
    return
  fi

  if ! command -v bc >/dev/null 2>&1; then
    echo -e "${RED}'bc' is required for reward math.${RESET}"
    read -r
    menu
    return
  fi

  OG_EVM_RPC="${OG_EVM_RPC:-https://evmrpc.0g.ai}"
  STAKING_ADDRESS="${STAKING_ADDRESS:-0xea224dBB52F57752044c0C86aD50930091F561B9}"
  GV_VALIDATOR_ADDR="${GV_VALIDATOR_ADDR:-0x108e619dA0cdbA8A301A53948A4aCc23A3d79377}"
  GV_VALIDATOR_PUBKEY="${GV_VALIDATOR_PUBKEY:-0xb589c0c26210a065a4c4aee068346301490efad5bfaa0578f186c6e41cc4018004f08a411ef0f056468174c260307b7e}"

  echo -e "${CYAN}Staking Rewards Management (0G Mainnet)${RESET}"
  echo "Select how to specify the validator:"
  echo "  1) Enter validator contract address (0x...)"
  echo "  2) Enter validator PUBKEY (48-byte) and resolve via Staking.getValidator(bytes)"
  echo "  3) Use Grand Valley defaults from ENV (GV_VALIDATOR_ADDR / GV_VALIDATOR_PUBKEY)"
  read -rp "Choice [1/2/3, b=back]: " MODE
  if [[ "${MODE,,}" == "b" || "${MODE,,}" == "back" ]]; then menu; return; fi

  VALIDATOR_ADDR=""
  case "${MODE:-3}" in
    1)
      read -rp "Validator contract address (0x...): " VALIDATOR_ADDR
      ;;
    2)
      read -rp "Validator PUBKEY (0x... 48-byte): " VAL_PUBKEY
      VALIDATOR_ADDR=$(cast call "$STAKING_ADDRESS" 'getValidator(bytes)(address)' "$VAL_PUBKEY" --rpc-url "$OG_EVM_RPC" | staking_rewards_first_token)
      [[ -z "$VALIDATOR_ADDR" || "$VALIDATOR_ADDR" == "0x0000000000000000000000000000000000000000" ]] && { echo -e "${RED}Validator not found for the provided PUBKEY.${RESET}"; return 1; }
      ;;
    3|*)
      if [ -n "$GV_VALIDATOR_ADDR" ]; then
        VALIDATOR_ADDR="$GV_VALIDATOR_ADDR"
      elif [ -n "$GV_VALIDATOR_PUBKEY" ]; then
        VALIDATOR_ADDR=$(cast call "$STAKING_ADDRESS" 'getValidator(bytes)(address)' "$GV_VALIDATOR_PUBKEY" --rpc-url "$OG_EVM_RPC" | staking_rewards_first_token)
        [[ -z "$VALIDATOR_ADDR" || "$VALIDATOR_ADDR" == "0x0000000000000000000000000000000000000000" ]] && { echo -e "${RED}Validator not found for GV_VALIDATOR_PUBKEY.${RESET}"; return 1; }
      else
        echo -e "${RED}GV_VALIDATOR_ADDR / GV_VALIDATOR_PUBKEY not set.${RESET}"
        return 1
      fi
      ;;
  esac

  read -rp "Custom EVM RPC? [Enter to use ${OG_EVM_RPC}, b=back]: " RPC_INPUT
  if [[ "${RPC_INPUT,,}" == "b" || "${RPC_INPUT,,}" == "back" ]]; then menu; return; fi
  if [ -n "${RPC_INPUT}" ]; then OG_EVM_RPC="$RPC_INPUT"; fi

  while true; do
    echo -e "\n${CYAN}Staking Rewards Management (0G Mainnet)${RESET}"
    echo "Validator: $VALIDATOR_ADDR"
    echo "RPC:       $OG_EVM_RPC"
    echo "  1) Validator earnings dashboard (read-only)"
    echo "  2) My delegation value & estimated rewards (read-only)"
    echo "  3) Withdraw commission (operator only)"
    echo "  4) Withdraw tip fees (operator only)"
    echo "  5) Trigger distributeRewards()"
    echo "  6) View withdrawal queue status (read-only)"
    echo "  7) Process withdrawal queue / failed stack"
    echo "  8) Change validator commission rate (operator only)"
    echo "  b) Back to main menu"
    read -rp "Choice: " REWARD_OPTION

    case "${REWARD_OPTION,,}" in
      1)
        local tokens delegator_shares stakes rewards commission tip_fee commission_rate apy operator withdrawal_fee
        tokens=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'tokens()(uint256)' || echo "N/A")
        delegator_shares=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'delegatorShares()(uint256)' || echo "N/A")
        stakes=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'stakes()(uint256)' || echo "N/A")
        rewards=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'rewards()(uint256)' || echo "N/A")
        commission=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'commission()(uint256)' || echo "N/A")
        tip_fee=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'tipFee()(uint256)' || echo "N/A")
        commission_rate=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'commissionRate()(uint32)' || echo "N/A")
        apy=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'annualPercentageYield()(uint256)' || echo "N/A")
        operator=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'operatorAddress()(address)' || echo "N/A")
        withdrawal_fee=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'withdrawalFeeInGwei()(uint96)' || echo "N/A")

        echo -e "\n${GREEN}Validator earnings dashboard:${RESET}"
        echo "  Total delegated tokens:        $(staking_rewards_display_og "$tokens") OG"
        echo "  Total delegator shares:        $delegator_shares"
        echo "  Actively staked:               $(staking_rewards_display_og "$stakes") OG"
        echo "  Pending rewards distribution:  $(staking_rewards_display_og "$rewards") OG"
        echo "  Operator commission:           $(staking_rewards_display_og "$commission") OG"
        echo "  Tip fees:                      $(staking_rewards_display_og "$tip_fee") OG"
        echo "  Commission rate:               $(staking_rewards_decimal_div "$commission_rate" 10000 4)%"
        echo "  Annual percentage yield:       $(staking_rewards_decimal_div "$apy" 100 2)%"
        echo "  Operator address:              $operator"
        echo "  Withdrawal fee:                $withdrawal_fee gwei"
        staking_rewards_pause
        ;;
      2)
        local delegator_addr my_shares current_wei principal_og principal_wei reward_wei reward_og
        read -rp "Delegator address (0x..., b=back): " delegator_addr
        if [[ "${delegator_addr,,}" == "b" || "${delegator_addr,,}" == "back" ]]; then continue; fi

        mapfile -t _DELEG_OUT < <(cast call "$VALIDATOR_ADDR" 'getDelegation(address)(address,uint256)' "$delegator_addr" --rpc-url "$OG_EVM_RPC")
        my_shares=$(echo "${_DELEG_OUT[-1]}" | awk '{print $1}' | tr -d '[:space:]')

        if [[ -z "$my_shares" || "$my_shares" == "0" ]]; then
          echo -e "${YELLOW}No active delegation found for this address.${RESET}"
          staking_rewards_pause
          continue
        fi

        current_wei=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'convertToTokens(uint256)(uint256)' "$my_shares" || echo "N/A")
        echo -e "\n${GREEN}Delegation value:${RESET}"
        echo "  Delegator:      $delegator_addr"
        echo "  Shares:         $my_shares"
        echo "  Current value:  $(staking_rewards_display_og "$current_wei") OG"
        echo "  Note: pending rewards() not yet distributed are excluded until distributeRewards() runs."

        read -rp "Original delegated amount in OG (Enter to skip, b=back): " principal_og
        if [[ "${principal_og,,}" == "b" || "${principal_og,,}" == "back" ]]; then continue; fi
        if [ -n "$principal_og" ]; then
          if [[ ! "$principal_og" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            echo -e "${RED}Invalid amount. Skipping reward estimate.${RESET}"
          elif [[ "$current_wei" =~ ^[0-9]+$ ]]; then
            principal_wei=$(cast to-wei "$principal_og" ether)
            reward_wei=$(echo "$current_wei - $principal_wei" | bc)
            if [ "$(echo "$reward_wei > 0" | bc)" = "1" ]; then
              reward_og=$(staking_rewards_display_og "$reward_wei")
              echo "  Estimated rewards above principal: $reward_og OG"
              echo "  To withdraw rewards only, undelegate about $reward_og OG."
              read -rp "Type 'w' to open undelegate flow, or Enter to stay here: " _jump
              if [[ "${_jump,,}" == "w" ]]; then
                undelegate_from_validator
                return
              fi
            else
              echo "  Estimated rewards above principal: 0 OG (current value is not above principal)."
            fi
          fi
        fi
        staking_rewards_pause
        ;;
      3)
        local commission_wei operator_addr recipient ok
        commission_wei=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'commission()(uint256)' || echo "0")
        echo -e "\n${GREEN}Accrued commission:${RESET} $(staking_rewards_display_og "$commission_wei") OG"

        if staking_rewards_bigint_lt "$commission_wei" "1000000000"; then
          echo -e "${YELLOW}Commission is below the 1 gwei minimum. Nothing to withdraw yet.${RESET}"
          staking_rewards_pause
          continue
        fi

        operator_addr=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'operatorAddress()(address)' || echo "")
        staking_rewards_operator_warning "$operator_addr"
        read -rp "Withdrawal recipient [Enter to use operator $operator_addr, b=back]: " recipient
        if [[ "${recipient,,}" == "b" || "${recipient,,}" == "back" ]]; then continue; fi
        recipient="${recipient:-$operator_addr}"

        echo -e "\n${YELLOW}Summary:${RESET}"
        echo "  Validator:  $VALIDATOR_ADDR"
        echo "  Recipient:  $recipient"
        echo "  Commission: $(staking_rewards_display_og "$commission_wei") OG"
        echo "  RPC:        $OG_EVM_RPC"
        echo "  Note:       commission withdrawal is queued, not instant."
        read -rp "Withdraw commission? (y/n, b=back): " ok
        case "${ok,,}" in
          y|yes) ;;
          b|back) continue ;;
          *) echo -e "${RED}Cancelled.${RESET}"; staking_rewards_pause; continue ;;
        esac

        if command -v cast >/dev/null 2>&1 ; then
          staking_rewards_send_no_value "$VALIDATOR_ADDR" 'withdrawCommission(address)' "Commission withdrawal" "$recipient"
          echo -e "${YELLOW}Commission withdrawal is QUEUED, not instant. It enters the withdrawal queue and completes after the network delay period. Check status via sub-option 6; run sub-option 7 if it is ready but unprocessed.${RESET}"
        else
          echo -e "${YELLOW}Manual path (Chainscan UI):${RESET}"
          echo "  1) Open https://chainscan.0g.ai/address/$VALIDATOR_ADDR"
          echo "  2) Contract -> Write -> select 'withdrawCommission(address)'"
          echo "  3) Set withdrawalAddress = $recipient"
          echo "  4) Connect the operator wallet and submit. No payable value is required."
          echo "  5) This withdrawal is queued, not instant."
        fi
        staking_rewards_pause
        ;;
      4)
        local tip_fee_wei operator_addr recipient ok
        tip_fee_wei=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'tipFee()(uint256)' || echo "0")
        echo -e "\n${GREEN}Withdrawable tip fees:${RESET} $(staking_rewards_display_og "$tip_fee_wei") OG"

        if [[ "$tip_fee_wei" == "0" ]]; then
          echo -e "${YELLOW}No tip fees to withdraw yet.${RESET}"
          staking_rewards_pause
          continue
        fi

        operator_addr=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'operatorAddress()(address)' || echo "")
        staking_rewards_operator_warning "$operator_addr"
        read -rp "Withdrawal recipient [Enter to use operator $operator_addr, b=back]: " recipient
        if [[ "${recipient,,}" == "b" || "${recipient,,}" == "back" ]]; then continue; fi
        recipient="${recipient:-$operator_addr}"

        echo -e "\n${YELLOW}Summary:${RESET}"
        echo "  Validator:  $VALIDATOR_ADDR"
        echo "  Recipient:  $recipient"
        echo "  Tip fees:   $(staking_rewards_display_og "$tip_fee_wei") OG"
        echo "  RPC:        $OG_EVM_RPC"
        echo "  Note:       tip fee withdrawal is instant, not queued."
        read -rp "Withdraw tip fees? (y/n, b=back): " ok
        case "${ok,,}" in
          y|yes) ;;
          b|back) continue ;;
          *) echo -e "${RED}Cancelled.${RESET}"; staking_rewards_pause; continue ;;
        esac

        if command -v cast >/dev/null 2>&1 ; then
          staking_rewards_send_no_value "$VALIDATOR_ADDR" 'withdrawTipFee(address)' "Tip fee withdrawal" "$recipient"
          echo -e "${GREEN}Tip fee withdrawal is instant and does not enter the withdrawal queue.${RESET}"
        else
          echo -e "${YELLOW}Manual path (Chainscan UI):${RESET}"
          echo "  1) Open https://chainscan.0g.ai/address/$VALIDATOR_ADDR"
          echo "  2) Contract -> Write -> select 'withdrawTipFee(address)'"
          echo "  3) Set withdrawalAddress = $recipient"
          echo "  4) Connect the operator wallet and submit. No payable value is required."
          echo "  5) This transfer is instant and is not queued."
        fi
        staking_rewards_pause
        ;;
      5)
        local rewards_wei ok
        rewards_wei=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'rewards()(uint256)' || echo "N/A")
        echo -e "\n${GREEN}Pending rewards before distribution:${RESET} $(staking_rewards_display_og "$rewards_wei") OG"
        echo "distributeRewards() folds pending rewards into the pool after community tax and validator commission."
        echo "Delegators receive rewards through a higher token/share exchange rate."
        read -rp "Trigger distributeRewards()? (y/n, b=back): " ok
        case "${ok,,}" in
          y|yes) ;;
          b|back) continue ;;
          *) echo -e "${RED}Cancelled.${RESET}"; staking_rewards_pause; continue ;;
        esac

        if command -v cast >/dev/null 2>&1 ; then
          staking_rewards_send_no_value "$VALIDATOR_ADDR" 'distributeRewards()' "distributeRewards"
        else
          echo -e "${YELLOW}Manual path (Chainscan UI):${RESET}"
          echo "  1) Open https://chainscan.0g.ai/address/$VALIDATOR_ADDR"
          echo "  2) Contract -> Write -> select 'distributeRewards()'"
          echo "  3) Connect any funded wallet and submit. No payable value is required."
        fi
        staking_rewards_pause
        ;;
      6)
        local withdraw_count current_block failed_count failed_amount next_amount display_count i row completion delegator amount status
        local sample_blocks sample_elapsed avg_block_seconds rate_bps block_time_note blocks_remaining eta_seconds eta_display
        withdraw_count=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'withdrawCount()(uint64)' || echo "0")
        current_block=$(cast block-number --rpc-url "$OG_EVM_RPC" 2>/dev/null || echo "N/A")
        failed_count=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'failedWithdrawCount()(uint256)' || echo "N/A")
        failed_amount=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'failedWithdrawAmount()(uint256)' || echo "N/A")
        next_amount=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'nextWithdrawalAmount()(uint256)' || echo "N/A")
        block_time_note="N/A"

        if [[ "$current_block" =~ ^[0-9]+$ ]] && command -v cast >/dev/null 2>&1; then
          if read -r sample_blocks sample_elapsed < <(staking_rewards_block_time_sample "$current_block" 200); then
            avg_block_seconds=$(awk -v elapsed="$sample_elapsed" -v blocks="$sample_blocks" 'BEGIN { printf "%.2f", elapsed / blocks }')
            rate_bps=$(awk -v elapsed="$sample_elapsed" -v blocks="$sample_blocks" 'BEGIN { printf "%.3f", blocks / elapsed }')
            block_time_note="${avg_block_seconds}s/block (${rate_bps} blocks/sec, sampled ${sample_blocks} blocks)"
          fi
        fi

        echo -e "\n${GREEN}Withdrawal queue status:${RESET}"
        echo "  Current block:          $current_block"
        echo "  Block time estimate:    $block_time_note"
        echo "  Withdrawal count:       $withdraw_count"
        echo "  Failed withdraw count:  $failed_count"
        echo "  Failed withdraw amount: $(staking_rewards_display_og "$failed_amount") OG"
        echo "  Next withdrawal amount: $(staking_rewards_display_og "$next_amount") OG"

        if [[ "$withdraw_count" =~ ^[0-9]+$ ]] && [ "$withdraw_count" -gt 0 ]; then
          display_count="$withdraw_count"
          if [ "$display_count" -gt 20 ]; then display_count=20; fi
          echo -e "\n${CYAN}Withdrawal queue entries:${RESET}"
          for ((i=0; i<display_count; i++)); do
            set +e
            mapfile -t row < <(cast call "$VALIDATOR_ADDR" 'getWithdraw(uint64)(uint256,address,uint256)' "$i" --rpc-url "$OG_EVM_RPC" 2>/dev/null)
            set -e
            if [ "${#row[@]}" -lt 3 ]; then
              echo "#$i"
              echo "  Status:     N/A"
              echo "  Completion: N/A"
              echo "  Delegator:  N/A"
              echo "  Amount:     N/A"
              continue
            fi
            completion=$(echo "${row[0]}" | awk '{print $1}' | tr -d '[:space:]')
            delegator=$(echo "${row[1]}" | awk '{print $1}' | tr -d '[:space:]')
            amount=$(echo "${row[2]}" | awk '{print $1}' | tr -d '[:space:]')
            status="PENDING"
            blocks_remaining="N/A"
            eta_display="N/A"
            if [[ "$completion" =~ ^[0-9]+$ && "$current_block" =~ ^[0-9]+$ ]] && [ "$completion" -le "$current_block" ]; then
              status="READY"
              blocks_remaining="0"
              eta_display="ready now"
            elif [[ "$completion" =~ ^[0-9]+$ && "$current_block" =~ ^[0-9]+$ ]]; then
              blocks_remaining=$((completion - current_block))
              if [[ "${sample_blocks:-}" =~ ^[0-9]+$ && "${sample_elapsed:-}" =~ ^[0-9]+$ && "$sample_blocks" -gt 0 ]]; then
                eta_seconds=$(((blocks_remaining * sample_elapsed + sample_blocks - 1) / sample_blocks))
                eta_display="$(staking_rewards_format_duration "$eta_seconds")"
              fi
            fi

            echo "#$i"
            echo "  Status:            $status"
            echo "  Completion height: $completion"
            echo "  Blocks remaining:  $blocks_remaining"
            echo "  Estimated wait:    $eta_display"
            echo "  Delegator:         $delegator"
            echo "  Amount:            $(staking_rewards_display_og "$amount") OG"
          done
          if [ "$withdraw_count" -gt 20 ]; then
            echo "Showing first 20 queue entries only."
          fi
        fi
        staking_rewards_pause
        ;;
      7)
        local ok failed_count
        echo -e "\n${YELLOW}processWithdrawQueue() is anyone-callable, but still spends gas.${RESET}"
        read -rp "Process ready withdrawal queue now? (y/n, b=back): " ok
        case "${ok,,}" in
          y|yes) ;;
          b|back) continue ;;
          *) echo -e "${RED}Cancelled.${RESET}"; staking_rewards_pause; continue ;;
        esac

        if command -v cast >/dev/null 2>&1 ; then
          staking_rewards_send_no_value "$VALIDATOR_ADDR" 'processWithdrawQueue()' "processWithdrawQueue"
        else
          echo -e "${YELLOW}Manual path (Chainscan UI):${RESET}"
          echo "  1) Open https://chainscan.0g.ai/address/$VALIDATOR_ADDR"
          echo "  2) Contract -> Write -> select 'processWithdrawQueue()'"
          echo "  3) Connect any funded wallet and submit. No payable value is required."
        fi

        failed_count=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'failedWithdrawCount()(uint256)' || echo "0")
        if [[ "$failed_count" =~ ^[0-9]+$ ]] && [ "$failed_count" -gt 0 ]; then
          read -rp "Failed withdraw stack has $failed_count entries. Process failed stack too? (y/n): " ok
          if [[ "${ok,,}" == "y" || "${ok,,}" == "yes" ]]; then
            if command -v cast >/dev/null 2>&1 ; then
              staking_rewards_send_no_value "$VALIDATOR_ADDR" 'processFailedWithdrawStack()' "processFailedWithdrawStack"
            else
              echo -e "${YELLOW}Manual path (Chainscan UI):${RESET}"
              echo "  1) Open https://chainscan.0g.ai/address/$VALIDATOR_ADDR"
              echo "  2) Contract -> Write -> select 'processFailedWithdrawStack()'"
              echo "  3) Connect any funded wallet and submit. No payable value is required."
            fi
          fi
        fi
        staking_rewards_pause
        ;;
      8)
        local current_rate_ppm new_rate_percent new_rate_ppm operator_addr ok
        current_rate_ppm=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'commissionRate()(uint32)' || echo "N/A")
        operator_addr=$(staking_rewards_safe_call "$VALIDATOR_ADDR" 'operatorAddress()(address)' || echo "N/A")

        if [[ ! "$current_rate_ppm" =~ ^[0-9]+$ ]]; then
          echo -e "${RED}Could not read the current commission rate. No transaction was prepared.${RESET}"
          staking_rewards_pause
          continue
        fi

        echo -e "\n${GREEN}Current validator commission:${RESET}"
        echo "  Rate:     $(staking_rewards_decimal_div "$current_rate_ppm" 10000 4)% ($current_rate_ppm ppm)"
        echo "  Operator: $operator_addr"
        read -rp "New commission rate in % (0-100, up to 4 decimals; b=back): " new_rate_percent
        if [[ "${new_rate_percent,,}" == "b" || "${new_rate_percent,,}" == "back" ]]; then continue; fi
        if ! new_rate_ppm=$(staking_rewards_percent_to_ppm "$new_rate_percent"); then
          echo -e "${RED}Invalid commission rate. Enter 0-100 with no more than 4 decimal places.${RESET}"
          staking_rewards_pause
          continue
        fi
        if [ "$new_rate_ppm" -eq "$current_rate_ppm" ]; then
          echo -e "${YELLOW}New commission rate matches the current rate. Nothing to change.${RESET}"
          staking_rewards_pause
          continue
        fi

        staking_rewards_operator_warning "$operator_addr"
        echo -e "\n${YELLOW}Commission rate change summary:${RESET}"
        echo "  Validator: $VALIDATOR_ADDR"
        echo "  Operator:  $operator_addr"
        echo "  Current:   $(staking_rewards_decimal_div "$current_rate_ppm" 10000 4)% ($current_rate_ppm ppm)"
        echo "  New:       $(staking_rewards_decimal_div "$new_rate_ppm" 10000 4)% ($new_rate_ppm ppm)"
        echo "  RPC:       $OG_EVM_RPC"
        echo "  Note:      the validator contract enforces the protocol maximum."
        read -rp "Submit commission rate change? (y/n, b=back): " ok
        case "${ok,,}" in
          y|yes) ;;
          b|back) continue ;;
          *) echo -e "${RED}Cancelled.${RESET}"; staking_rewards_pause; continue ;;
        esac

        if command -v cast >/dev/null 2>&1 ; then
          staking_rewards_send_no_value "$VALIDATOR_ADDR" 'setCommissionRate(uint32)' "Commission rate change" "$new_rate_ppm"
        else
          echo -e "${YELLOW}Manual path (Chainscan UI):${RESET}"
          echo "  1) Open https://chainscan.0g.ai/address/$VALIDATOR_ADDR"
          echo "  2) Contract -> Write -> select 'setCommissionRate(uint32)'"
          echo "  3) Set commissionRate_ = $new_rate_ppm (ppm, equal to ${new_rate_percent}%)"
          echo "  4) Connect the validator operator wallet and submit. No payable value is required."
        fi
        staking_rewards_pause
        ;;
      b|back)
        menu
        return
        ;;
      *)
        echo -e "${RED}Invalid option.${RESET}"
        ;;
    esac
  done
}

function query_balance() {
    echo -e "${CYAN}Select an option:${RESET}"
    echo "1. Query balance of EVM address"
    echo "2. Back"
    read -p "Enter your choice (1 or 2): " choice

    case $choice in
        1)
            read -p "Enter the EVM address to query: " evm_address
            ;;
        2)
            menu
            return
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${RESET}"
            query_balance
            return
            ;;
    esac

    echo -e "${CYAN}Fetching balance from mainnet RPC for $evm_address...${RESET}"
    curl -s --insecure -X POST https://lightnode-json-rpc-mainnet-0g.grandvalleys.com \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\":\"2.0\",
            \"method\":\"eth_getBalance\",
            \"params\": [\"$evm_address\", \"latest\"],
            \"id\":16661
        }" | jq -r '.result' | awk '{printf "Balance of %s: %0.18f 0G\n", "'"$evm_address"'", strtonum($1)/1e18}'

    echo -e "\n${YELLOW}Press Enter to go back to main menu...${RESET}"
    read -r
    menu
}

# function send_transaction() {
#     echo -e "\n${YELLOW}Available wallets:${RESET}"
#     0gchaind keys list
#
#     read -p "Enter sender wallet name: " SENDER_WALLET
#     read -p "Enter recipient wallet address: " RECIPIENT_ADDRESS
#     read -p "Enter amount to send (in AOGI, e.g. 10 = 10 AOGI): " AMOUNT_AOGI
#
#     AMOUNT_UAOGI=$(awk "BEGIN { printf \"%.0f\", $AMOUNT_AOGI * 1000000 }")
#
#     0gchaind tx bank send "$SENDER_WALLET" "$RECIPIENT_ADDRESS" "${AMOUNT_UAOGI}u0G" --chain-id "$OG_CHAIN_ID" --gas auto --gas-adjustment 1.5 -y
#
#     menu
# }

# function stake_tokens() {
#     echo -e "\n${YELLOW}Available wallets:${RESET}"
#     0gchaind keys list
#
#     DEFAULT_WALLET=$WALLET
#
#     read -p "Enter wallet name (leave empty to use current default wallet --> $DEFAULT_WALLET): " WALLET_NAME
#     if [ -z "$WALLET_NAME" ]; then
#         WALLET_NAME=$DEFAULT_WALLET
#     fi
#
#     echo "Choose an option:"
#     echo "1. Delegate to Grand Valley"
#     echo "2. Self-delegate"
#     echo "3. Delegate to another validator"
#     read -p "Enter your choice (1, 2, or 3): " CHOICE
#
#     # Prompt for RPC choice
#     read -p "Use your own RPC or Grand Valley's? (own/gv, leave empty for gv): " RPC_CHOICE
#     if [ -z "$RPC_CHOICE" ]; then
#         RPC_CHOICE="gv"
#     fi
#
#     case $CHOICE in
#         1)
#             read -p "Enter amount to stake (in AOGI, e.g. 10 = 10 AOGI): " AMOUNT_AOGI
#             VAL="0gvaloper1gela3jtnmen0dmj2q5p0pne5y45ftshzs053x3"
#             ;;
#         2)
#             read -p "Enter amount to stake (in AOGI, e.g. 10 = 10 AOGI): " AMOUNT_AOGI
#             VAL=$(0gchaind keys show "$WALLET_NAME" --bech val -a)
#             ;;
#         3)
#             read -p "Enter validator address: " VAL
#             read -p "Enter amount to stake (in AOGI, e.g. 10 = 10 AOGI): " AMOUNT_AOGI
#             ;;
#         *)
#             echo "Invalid choice. Please enter 1, 2, or 3."
#             menu
#             return
#             ;;
#     esac
#
#     AMOUNT_UAOGI=$(awk "BEGIN { printf \"%.0f\", $AMOUNT_AOGI * 1000000 }")
#
#     if [ "$RPC_CHOICE" == "gv" ]; then
#         NODE="--node https://lightnode-rpc-mainnet-0g.grandvalleys.com:443"
#     else
#         NODE=""
#     fi
#
#     0gchaind tx staking delegate "$VAL" "${AMOUNT_UAOGI}u0G" --from "$WALLET_NAME" --chain-id "$OG_CHAIN_ID" --gas auto --gas-adjustment 1.5 $NODE -y
#
#     menu
# }

# function unstake_tokens() {
#     echo -e "\n${YELLOW}Available wallets:${RESET}"
#     0gchaind keys list
#
#     DEFAULT_WALLET=$WALLET
#
#     read -p "Enter wallet name (leave empty to use current default wallet --> $DEFAULT_WALLET): " WALLET_NAME
#     if [ -z "$WALLET_NAME" ]; then
#         WALLET_NAME=$DEFAULT_WALLET
#     fi
#
#     read -p "Enter validator address: " VALIDATOR_ADDRESS
#     read -p "Enter amount to unstake (in AOGI, e.g. 10 = 10 AOGI): " AMOUNT_AOGI
#
#     # Prompt for RPC choice
#     read -p "Use your own RPC or Grand Valley's? (own/gv, leave empty for gv): " RPC_CHOICE
#     if [ -z "$RPC_CHOICE" ]; then
#         RPC_CHOICE="gv"
#     fi
#
#     AMOUNT_UAOGI=$(awk "BEGIN { printf \"%.0f\", $AMOUNT_AOGI * 1000000 }")
#
#     if [ "$RPC_CHOICE" == "gv" ]; then
#         NODE="--node https://lightnode-rpc-mainnet-0g.grandvalleys.com:443"
#     else
#         NODE=""
#     fi
#
#     0gchaind tx staking unbond "$VALIDATOR_ADDRESS" "${AMOUNT_UAOGI}u0G" --from "$WALLET_NAME" --chain-id "$OG_CHAIN_ID" --gas auto --gas-adjustment 1.5 $NODE -y
#
#     menu
# }

# function unjail_validator() {
#     echo -e "\n${YELLOW}Available wallets:${RESET}"
#     0gchaind keys list
#
#     DEFAULT_WALLET=$WALLET
#
#     read -p "Enter wallet name to unjail (leave empty to use default --> $DEFAULT_WALLET): " WALLET_NAME
#     if [ -z "$WALLET_NAME" ]; then
#         WALLET_NAME=$DEFAULT_WALLET
#     fi
#
#     # Prompt for RPC choice
#     read -p "Use your own RPC or Grand Valley's? (own/gv, leave empty for gv): " RPC_CHOICE
#     if [ -z "$RPC_CHOICE" ]; then
#         RPC_CHOICE="gv"
#     fi
#
#     if [ "$RPC_CHOICE" == "gv" ]; then
#         NODE="--node https://lightnode-rpc-mainnet-0g.grandvalleys.com:443"
#     else
#         NODE=""
#     fi
#
#     0gchaind tx slashing unjail --from "$WALLET_NAME" --chain-id "$OG_CHAIN_ID" --gas-adjustment 1.6 --gas auto --gas-prices 0.003u0G $NODE -y
#
#     menu
# }

# function export_evm_private_key() {
#     read -p "Enter wallet name: " WALLET_NAME
#     0gchaind keys unsafe-export-eth-key $WALLET_NAME
#     echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
#     read -r
#     menu
# }

# function restore_wallet() {
#     read -p "Enter wallet name: " WALLET_NAME
#     0gchaind keys add $WALLET_NAME --recover --eth
#     menu
# }

# function create_wallet() {
#     read -p "Enter wallet name: " WALLET_NAME
#     0gchaind keys add $WALLET_NAME --eth
#     menu
# }

function ensure_evm_cli_tools() {
  # Modes:
  #  - check:   only check and report; never install
  #  - prompt:  prompt to install if missing (default)
  #  - require: prompt to install; fail if still missing
  local mode="${1:-prompt}"
  local missing_bc=0
  local missing_cast=0
  local foundry_bin="$HOME/.foundry/bin"
  local export_line='export PATH="$HOME/.foundry/bin:$PATH"'

  # Persist PATH for future shells
  _persist_foundry_path() {
    for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
      if [ -e "$f" ]; then
        grep -qs 'foundry/bin' "$f" || echo "$export_line" >> "$f"
      else
        echo "$export_line" >> "$f"
      fi
    done
  }

  # Activate in current shell
  _activate_foundry_in_session() {
    export PATH="$foundry_bin:$PATH"
    hash -r 2>/dev/null || true
  }

  # Check bc
  if ! command -v bc >/dev/null 2>&1; then
    missing_bc=1
    if [ "$mode" != "check" ]; then
      echo -e "${YELLOW}'bc' is required for calculations but not found.${RESET}"
      read -p "Install 'bc' now? (y/n, b=back): " ans
      case "${ans,,}" in
        y|yes)
          if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -y && sudo apt-get install -y bc || true
          elif command -v brew >/dev/null 2>&1; then
            brew install bc || true
          else
            echo -e "${RED}Automatic installation not supported on this system.${RESET}"
          fi
          ;;
        b|back) return 1 ;;
        *) : ;;
      esac
      command -v bc >/dev/null 2>&1 || missing_bc=1
      [ $missing_bc -eq 0 ] && echo -e "${GREEN}'bc' is installed.${RESET}"
    fi
  fi

  # If Foundry exists but PATH isn't set, activate it
  if ! command -v cast >/dev/null 2>&1 && [ -x "$foundry_bin/cast" ]; then
    _activate_foundry_in_session
  fi

  # Check cast (Foundry)
  if ! command -v cast >/dev/null 2>&1; then
    missing_cast=1
    if [ "$mode" != "check" ]; then
      echo -e "${YELLOW}'cast' (Foundry) is required for EVM RPC/tx, but not found.${RESET}"
      read -p "Install Foundry (provides 'cast') now? (y/n, b=back): " ans
      case "${ans,,}" in
        y|yes)
          # Bootstrap Foundry if needed
          if [ ! -x "$foundry_bin/foundryup" ]; then
            (curl -L https://foundry.paradigm.xyz | bash) || true
          fi
          # Activate + persist PATH
          _activate_foundry_in_session
          _persist_foundry_path
          # Install/update binaries non-interactively
          if [ -x "$foundry_bin/foundryup" ]; then
            "$foundry_bin/foundryup" || true
          fi
          # Re-activate (in case PATH changed)
          _activate_foundry_in_session
          ;;
        b|back) return 1 ;;
        *) : ;;
      esac
      command -v cast >/dev/null 2>&1 || missing_cast=1
      [ $missing_cast -eq 0 ] && echo -e "${GREEN}'cast' is installed and on PATH.${RESET}"
    fi
  fi

  # Require mode: enforce availability
  if [ "$mode" = "require" ]; then
    if [ $missing_bc -ne 0 ] || [ $missing_cast -ne 0 ]; then
      echo -e "${RED}Required tools are missing ('bc' and/or 'cast').${RESET}"
      return 1
    fi
  fi

  return 0
}

# Valley no longer reads or persists EVM wallet private keys. Detect only the
# legacy entry name so operators can migrate it without exposing its value.
function warn_legacy_private_key_file() {
  local env_file="${OG_HOME:-$HOME/.0gchaind/0g-home/0gchaind-home}/.env"
  if [ -f "$env_file" ] && grep -qE '^PRIVATE_KEY=' "$env_file" 2>/dev/null; then
    echo -e "${YELLOW}Legacy PRIVATE_KEY entry detected in $env_file.${RESET}"
    echo -e "${YELLOW}Valley will not read or use it. After confirming another signer path, remove that legacy entry securely.${RESET}"
  fi
}

function delete_validator_node() {
    local el_svc="${OG_GETH_SERVICE_NAME:-0g-geth}"
    if [ "${EXEC_CLIENT:-geth}" = "reth" ]; then
        el_svc="${OG_RETH_SERVICE_NAME:-0g-reth}"
    fi
    sudo systemctl stop ${OG_SERVICE_NAME} ${el_svc} 2>/dev/null || true
    sudo systemctl disable ${OG_SERVICE_NAME} ${el_svc} 2>/dev/null || true
    sudo rm -rf /etc/systemd/system/${OG_SERVICE_NAME}.service /etc/systemd/system/${el_svc}.service
    sudo rm -rf $HOME/aristotle
    sudo rm -rf $HOME/.0gchaind
    sudo rm -rf $HOME/aristotle-v1.0.4
    sed -i "/OG_/d" $HOME/.bash_profile
    sed -i "/EXEC_CLIENT/d" $HOME/.bash_profile
    sed -i "/RETH_/d" $HOME/.bash_profile
    echo "Validator node deleted successfully."
    menu
}

function show_validator_logs() {
    local el_svc="${OG_GETH_SERVICE_NAME:-0g-geth}"
    local client_name="Geth"
    if [ "${EXEC_CLIENT:-geth}" = "reth" ]; then
        el_svc="${OG_RETH_SERVICE_NAME:-0g-reth}"
        client_name="Reth"
    fi
    trap "echo \"Displaying Consensus Client and Execution Client ($client_name) Logs:\";" INT
    sudo journalctl -u ${OG_SERVICE_NAME} -u ${el_svc} -fn 100 -o cat || true
    trap - INT
    menu
}

function show_consensus_client_logs() {
    trap 'echo "Displaying Consensus Client Logs:";' INT
    sudo journalctl -u ${OG_SERVICE_NAME} -fn 100 --no-pager
    trap - INT
    menu
}

function show_geth_logs() {
    local el_svc="${OG_GETH_SERVICE_NAME:-0g-geth}"
    local client_name="Geth"
    if [ "${EXEC_CLIENT:-geth}" = "reth" ]; then
        el_svc="${OG_RETH_SERVICE_NAME:-0g-reth}"
        client_name="Reth"
    fi
    trap "echo \"Displaying Execution Client ($client_name) Logs:\";" INT
    sudo journalctl -u ${el_svc} -fn 100 --no-pager
    trap - INT
    menu
}

function show_node_status() {
    local port
    port=$(grep -oP 'laddr = "tcp://(0.0.0.0|127.0.0.1):\K[0-9]+57' "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml" 2>/dev/null || echo "26657")
    local consensus_status
    consensus_status=$(curl -s "http://127.0.0.1:$port/status" || true)
    if [ -n "$consensus_status" ]; then
        echo "$consensus_status" | jq 2>/dev/null || true
    fi
    local node_height
    node_height=$(echo "$consensus_status" | jq -r '.result.sync_info.latest_block_height // "0"' 2>/dev/null || echo "0")
    local consensus_peers
    consensus_peers=$(curl -s "http://127.0.0.1:$port/net_info" | jq -r '.result.n_peers // "0"' 2>/dev/null || echo "0")

    local client_name="Geth"
    if [ "${EXEC_CLIENT:-geth}" = "reth" ]; then
        client_name="Reth"
    fi

    # Query Execution Client via JSON-RPC HTTP
    local el_port="${OG_PORT:-26}545"
    local el_rpc_url="http://127.0.0.1:$el_port"
    local el_height_hex
    el_height_hex=$(curl -s -X POST "$el_rpc_url" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result' 2>/dev/null || echo "0x0")
    local el_block_height
    el_block_height=$(printf "%d" "$el_height_hex" 2>/dev/null || echo "0")

    local el_peers_hex
    el_peers_hex=$(curl -s -X POST "$el_rpc_url" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq -r '.result' 2>/dev/null || echo "0x0")
    local el_peers
    el_peers=$(printf "%d" "$el_peers_hex" 2>/dev/null || echo "0")

    local realtime_block_height
    realtime_block_height=$(curl -s -X POST "https://evmrpc.0g.ai" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result' | xargs printf "%d\n" 2>/dev/null || echo "0")

    echo "Consensus client block height: $node_height"
    echo "Execution client ($client_name) block height: $el_block_height"
    echo "Consensus client peers connected: $consensus_peers"
    echo "Execution client ($client_name) peers connected: $el_peers"
    local block_difference=$(( realtime_block_height - node_height ))
    echo "Real-time Block Height: $realtime_block_height"
    echo -e "${YELLOW}Block Difference:${RESET} $block_difference"

    # Add explanation for negative values
    if (( block_difference < 0 )); then
        echo -e "${GREEN}Note:${RESET} A negative value is normal - this means 0G Official's Mainnet RPC block height is currently behind your node's height"
    fi
    echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function migrate_geth_to_reth() {
    clear
    echo -e "${ORANGE}Migrating Geth to Reth Execution Client...${RESET}"
    if [ "${EXEC_CLIENT:-geth}" = "reth" ]; then
        echo -e "${YELLOW}Your execution client is already set to Reth in .bash_profile.${RESET}"
        read -p "Do you want to run the migration script anyway? (y/n): " force_mig
        if [[ "${force_mig,,}" != "y" ]]; then
            menu
            return
        fi
    fi
    
    local script_dir
    script_dir="$(dirname "${BASH_SOURCE[0]}")"
    if [ -f "$script_dir/0g_geth_to_reth_migrate.sh" ]; then
        bash "$script_dir/0g_geth_to_reth_migrate.sh"
    else
        run_repository_script resources/0g_geth_to_reth_migrate.sh
    fi
    menu
}

function rollback_align_height() {
    clear
    echo -e "${ORANGE}Rollback & Align CL/EL Height...${RESET}"
    if [ "${EXEC_CLIENT:-geth}" != "reth" ]; then
        echo -e "${YELLOW}Warning: This feature is designed for Reth execution client.${RESET}"
        read -p "Continue anyway? (y/n): " force_rb
        if [[ "${force_rb,,}" != "y" ]]; then
            menu
            return
        fi
    fi

    local script_dir
    script_dir="$(dirname "${BASH_SOURCE[0]}")"
    if [ -f "$script_dir/0g_rollback_align.sh" ]; then
        bash "$script_dir/0g_rollback_align.sh"
    else
        run_repository_script resources/0g_rollback_align.sh
    fi
    menu
}


function schedule_validator_node() {
    echo -e "${YELLOW}This feature will:${RESET}"
    echo -e "${GREEN}- Run:${RESET} sudo apt-get update"
    echo -e "${GREEN}- Install dependency:${RESET} at"
    echo -e "${GREEN}- Enable and start:${RESET} atd (scheduler service)"
    
    local el_svc="${OG_GETH_SERVICE_NAME:-0g-geth}"
    if [ "${EXEC_CLIENT:-geth}" = "reth" ]; then
        el_svc="${OG_RETH_SERVICE_NAME:-0g-reth}"
    fi
    echo -e "${GREEN}- Schedule:${RESET} stop/disable or restart/enable for ${CYAN}${OG_SERVICE_NAME}.service${RESET} + ${CYAN}${el_svc}.service${RESET} via ${ORANGE}at${RESET}"
    echo -e "${GREEN}- List or remove:${RESET} scheduled jobs from the at queue"
    echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
    read -r
    run_repository_script resources/0g_node_schedule.sh
    menu
}

function stop_validator_node() {
    local el_svc="${OG_GETH_SERVICE_NAME:-0g-geth}"
    if [ "${EXEC_CLIENT:-geth}" = "reth" ]; then
        el_svc="${OG_RETH_SERVICE_NAME:-0g-reth}"
    fi
    sudo systemctl stop ${OG_SERVICE_NAME} ${el_svc}
    menu
}

function restart_validator_node() {
    local el_svc="${OG_GETH_SERVICE_NAME:-0g-geth}"
    if [ "${EXEC_CLIENT:-geth}" = "reth" ]; then
        el_svc="${OG_RETH_SERVICE_NAME:-0g-reth}"
    fi
    sudo systemctl daemon-reload
    sudo systemctl restart ${OG_SERVICE_NAME} ${el_svc}
    menu
}

# function backup_validator_key() {
#     cp $HOME/.0gchain/config/priv_validator_key.json $HOME/priv_validator_key.json
#     echo -e "\n${YELLOW}Your priv_vaidator_key.json file has been copied to $HOME${RESET}"
#     menu
# }

function add_peers() {
    echo "Select an option:"
    echo "1. Add peers manually"
    echo "2. Use Grand Valley's peers"
    read -p "Enter your choice (1 or 2): " choice

    case $choice in
        1)
            read -p "Enter peers (comma-separated): " peers
            echo "You have entered the following peers: $peers"
            read -p "Do you want to proceed? (yes/no): " confirm   
            if [[ $confirm == "yes" ]]; then
                sed -i -e "s|^persistent_peers *=.*|persistent_peers = \"$peers\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
                echo "Peers added manually."
            else
                echo "Operation cancelled. Returning to menu."
                menu
            fi
            ;;
        2)
            peers=$(curl -sS https://lightnode-rpc-mainnet-0g.grandvalleys.com/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)
            echo "Grand Valley's peers: $peers"
            read -p "Do you want to proceed? (yes/no): " confirm
            if [[ $confirm == "yes" ]]; then
                sed -i -e "s|^persistent_peers *=.*|persistent_peers = \"813aeda202eae52b0d3e389a0e6e3a0354ad547a@peer-mainnet-0g.grandvalleys.com:28656,$peers\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
                echo "Grand Valley's peers added."
            else
                echo "Operation cancelled. Returning to menu."
                menu
            fi
            ;;
        *)
            echo "Invalid choice. Please enter 1 or 2."
            menu
            ;;
    esac
    echo "Now you can restart your Validator Node"
    menu
}

# Storage Node Functions
function deploy_storage_node() {
    run_repository_script resources/0g_storage_node_install.sh
    menu
}

function update_storage_node() {
    run_repository_script resources/0g_storage_node_update.sh
    menu
}

function apply_storage_node_snapshot() {
    clear
    # Display critical information
    echo -e "\033[0;31m▓▒░ CRITICAL NOTICE:\033[0m"
    echo -e "\033[0;33m░ Snapshot contains: \033[0;32mflow_db (blockchain data)\033[0m"
    echo -e "\033[0;33m░ Not included:      \033[38;5;214mdata_db (mining storage)\033[0m"
    echo -e "\033[0;32m░ Your data_db will auto-create when node starts\033[0m"
    echo -e "\033[0;31m░ \033[38;5;214m⚠ SECURITY WARNING: \033[0;31mNever use pre-made data_db!\033[0m"
    echo -e "\033[0;31m░               It would mine for someone else's wallet!\033[0m"
    echo -e "\033[0;36mDocumentation: \033[0;34mhttps://docs.0g.ai/run-a-node/storage-node#snapshot\033[0m\n"

    # Get explicit confirmation
    read -p $'\033[0;36mDo you accept these conditions? (y/N): \033[0m' agree
    if [[ "${agree,,}" != "y" ]]; then
        echo -e "\033[0;31mOperation cancelled by user\033[0m"
        sleep 1
        menu
        return
    fi

    # Contract selection loop
    while true; do
        clear
        echo -e "\033[0;36m▓▒░ Storage Node Contract Type\033[0m"
        echo -e "\033[0;32m1) Standard Contract\033[0m   (Not Available)"
        echo -e "\033[0;33m2) Turbo Contract\033[0m     (Available)"
        echo -e "\033[0;31m3) Cancel & Return\033[0m"
        
        read -p $'\033[0;34mSelect option [1-3]: \033[0m' contract_choice

        case $contract_choice in
            1)
                echo -e "\033[0;33mStandard Contract snapshot not available."
                echo -e "Please monitor official channels for updates!\033[0m"
                sleep 2
                ;;
            2)
                echo -e "\n\033[0;31m▓▒░ IMPORTANT: Post-Snapshot Downtime Expected ░▒▓\033[0m"
                echo -e "\033[0;33mAfter applying the snapshot, your storage node will experience"
                echo -e "several hours of downtime while the data_db automatically syncs."
                echo -e "This is NORMAL BEHAVIOR - no action is needed!\033[0m\n"
                echo -e "The node will resume normal operations once sync completes."
                echo -e "\033[0;36mProgress can be monitored via node logs.\033[0m"
                sleep 3

                echo -e "\n\033[0;32mInitializing Standard Contract snapshot...\033[0m"
                echo -e "\033[0;33mThis may take several minutes...\033[0m"
                run_repository_script resources/0g_turbo_zgs_node_snapshot.sh

                echo -e "\n\033[0;32m▓▒░ Snapshot Applied Successfully ░▒▓\033[0m"
                echo -e "\033[0;33mYour node is now syncing data_db - this will take several hours"
                echo -e "\033[0;31mDO NOT RESTART OR INTERRUPT THIS PROCESS\033[0m"
                echo -e "\033[0;33mMonitor progress with: \033[0;36mshow_storage_logs\033[0m"
                echo -e "Concerned? Check logs before contacting support!"
                sleep 3
                menu
                break
                ;;
            3)
                echo -e "\033[0;31mOperation aborted by user\033[0m"
                sleep 1
                menu
                break
                ;;
            *)
                echo -e "\033[0;31mInvalid selection! Please choose 1, 2, or 3.\033[0m"
                sleep 1
                ;;
        esac
    done
}

function delete_storage_node() {
    sudo systemctl stop zgs
    sudo systemctl disable zgs
    sudo rm -rf /etc/systemd/system/zgs.service
    sudo rm -r $HOME/0g-storage-node
    echo "Storage node deleted successfully."
    menu
}

function change_storage_node() {
    run_repository_script resources/0g_storage_node_change.sh
    menu
}

function show_storage_logs() {
    clear
    LOG_FILE="$HOME/0g-storage-node/run/log/zgs.log.$(TZ=UTC date +%Y-%m-%d)"
    
    # Verify log file exists
    if [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${RED}Error: Log file not found!${RESET}"
        echo -e "Verify node is running at: ${CYAN}$LOG_FILE${RESET}"
        sleep 2
        menu
        return
    fi

    # Show persistent instructions first
    echo -e "${CYAN}▓▒░ Storage Node Log Viewer ░▒▓${RESET}"
    echo -e "${YELLOW}┌────────────────────────────────────────────────────┐"
    echo -e "│ ${GREEN}Controls:${RESET}"
    echo -e "│ ${CYAN}Shift+F${RESET}                 - Auto-scroll new logs"
    echo -e "│ ${CYAN}Ctrl+C${RESET}                  - Pause auto-scroll"
    echo -e "│ ${CYAN}up arrow/down arrow${RESET}     - Scroll manually"
    echo -e "│ ${CYAN}/search${RESET}                 - Find text (n=next match)"
    echo -e "│ ${CYAN}Q${RESET}                       - Quit to menu"
    echo -e "└────────────────────────────────────────────────────┘${RESET}"
    
    # Wait for user confirmation
    read -n 1 -s -p $'\n\e[33mPress ANY KEY to view logs (Q to cancel): \e[0m' input
    echo ""
    
    if [[ "${input,,}" == "q" ]]; then
        echo -e "${GREEN}Operation cancelled. Returning to menu...${RESET}"
        sleep 1
        menu
        return
    fi

    # Show logs with instructions visible first
    echo -e "\n${CYAN}Loading logs...${RESET}"
    sleep 1  # Pause to see loading message
    less -R +F "$LOG_FILE"
    
    # Return to menu
    echo -e "\n${GREEN}Log viewing session closed. Returning to menu...${RESET}"
    sleep 1
    menu
}

function show_storage_status() {
    echo -e "${YELLOW}Storage Node Status:${RESET}"

    # Show Storage Node RPC Status
    curl -s -X POST http://localhost:5678 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}' \
        | jq

    config_file=$(sudo systemctl cat zgs | grep ExecStart | sed -E 's/.*--config[= ]([^ ]+)/\1/')

    if [[ -f "$config_file" ]]; then
        # Show ZGS node version
        if [[ -x "$HOME/0g-storage-node/target/release/zgs_node" ]]; then
            zgs_version=$("$HOME/0g-storage-node/target/release/zgs_node" --version)
            echo -e "\nZGS Node Version: ${GREEN}$zgs_version${RESET}"
        else
            echo -e "\n${RED}ZGS node binary not found or not executable!${RESET}"
        fi

        # Get blockchain RPC endpoint
        rpc_endpoint=$(grep -E '^blockchain_rpc_endpoint' "$config_file" | sed -E 's/.*= *"([^"]+)"/\1/')
        echo -e "\nBlockchain RPC Endpoint: ${GREEN}$rpc_endpoint${RESET}"

        # Get miner contract address
        contract_address=$(grep -E '^mine_contract_address' "$config_file" | sed -E 's/.*= *"([^"]+)"/\1/')
        echo -e "Miner Contract Address: ${GREEN}$contract_address${RESET}"

        # Detect contract type
        if [[ "$contract_address" == "0x1785c8683b3c527618eFfF78d876d9dCB4b70285" ]]; then
            echo -e "Contract Type: ${CYAN}Standard Contract${RESET}"
        elif [[ "$contract_address" == "0xCd01c5Cd953971CE4C2c9bFb95610236a7F414fe" ]]; then
            echo -e "Contract Type: ${CYAN}Turbo Contract${RESET}"
        else
            echo -e "Contract Type: ${RED}Unknown Contract${RESET}"
        fi

        # Get PoRA Transactions - UPDATED SECTION
        log_file="$HOME/0g-storage-node/run/log/zgs.log.$(TZ=UTC date +%Y-%m-%d)"
        if [[ -f "$log_file" ]]; then
            hit_value=$(tail -n 100 "$log_file" | grep -oP 'hit: \K\d+' | tail -n1)
            if [[ -n "$hit_value" ]]; then
                echo -e "\nLatest PoRA TXs Count: ${GREEN}$hit_value${RESET}"
            else
                echo -e "\nLatest PoRA TXs Count: ${RED}No valid hits found in recent logs${RESET}"
            fi
        else
            echo -e "\nLatest PoRA TXs Count: ${RED}Log file not found${RESET}"
        fi
    else
        echo -e "\n${RED}Config file not found! Unable to determine contract or RPC info.${RESET}"
    fi

    echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function stop_storage_node() {
    sudo systemctl stop zgs
    menu
}

function restart_storage_node() {
    sudo systemctl daemon-reload
    sudo systemctl restart zgs
    menu
}

# Storage KV Functions
function deploy_storage_kv() {
    run_repository_script resources/0g_storage_kv_install.sh
    menu
}

function show_storage_kv_logs() {
    sudo journalctl -u zgskv -fn 100
    menu
}

function delete_storage_kv() {
    sudo systemctl stop zgskv
    sudo systemctl disable zgskv
    sudo rm -rf /etc/systemd/system/zgskv.service
    sudo rm -r $HOME/0g-storage-kv
    echo "Storage KV deleted successfully."
    menu
}

function update_storage_kv() {
    run_repository_script resources/0g_storage_kv_update.sh
    menu
}

function stop_storage_kv() {
    sudo systemctl stop zgskv
    menu
}

function restart_storage_kv() {
    sudo systemctl daemon-reload
    sudo systemctl restart zgskv
    menu
}

# AI Alignment Node Functions
function run_ai_alignment_node() {
     run_repository_script resources/0g_ai_alignment_node_install.sh
     menu
}

function show_ai_alignment_logs() {
    echo -e "${GREEN}Showing AI Alignment Node Logs...${RESET}"
    # Service name used by installer: 0g-alignment-node
    sudo journalctl -u 0g-alignment-node -fn 100 --no-pager
    menu
}

function stop_ai_alignment_node() {
    sudo systemctl stop 0g-alignment-node
    menu
}

function delete_ai_alignment_node() {
    sudo systemctl stop 0g-alignment-node
    sudo systemctl disable 0g-alignment-node
    sudo rm -rf /etc/systemd/system/0g-alignment-node.service
    sudo rm -r $HOME/0g-alignment-node
    echo "AI Alignment Node deleted successfully."
    menu
}

function restart_ai_alignment_node() {
    sudo systemctl daemon-reload
    sudo systemctl restart 0g-alignment-node
    menu
}

# Approve AI Alignment Node delegations (bulk token-ids)
function approve_ai_alignment_node() {
    local APP_DIR="$HOME/0g-alignment-node"
    local BIN_PATH="$APP_DIR/0g-alignment-node"

    if [ ! -x "$BIN_PATH" ]; then
        echo -e "${YELLOW}Alignment node binary not found at ${BIN_PATH}.${RESET}"
        echo -e "Install/stage it first via: Run AI Alignment Node option."
    fi
    echo -e "${YELLOW}Automated Alignment approval is disabled by the Valley private-key boundary.${RESET}"
    echo "Upstream Alignment v1.0.0 exposes transaction signing through a raw --key argument."
    echo "Valley will not collect a wallet private key or place it in process arguments."
    echo "Review the official upstream procedure and execute the signing step manually if you accept that upstream limitation."
    read -p "Press Enter to return to menu..." _
    menu
}

# Show Grand Valley's Endpoints
function show_endpoints() {
    echo -e "$ENDPOINTS"
    echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function show_guidelines() {
    echo -e "${CYAN}Guidelines on How to Use the Valley of 0G${RESET}"
    echo -e "${YELLOW}This tool is designed to help you manage your 0G nodes. Below are the guidelines on how to use it effectively:${RESET}"
    
    echo -e "${GREEN}1. Navigating the Menu${RESET}"
    echo "   - The menu is divided into several sections: Validator Node, Storage Node, Storage KV, Node Management, and Utilities."
    echo "   - To select an option, you can either:"
    echo "     a. Enter the corresponding number followed by the letter (e.g., 1a for Deploy Validator Node)."
    echo "     b. Enter the number, press Enter, and then enter the letter (e.g., 1 then a)."

    echo -e "${GREEN}2. Entering Choices${RESET}"
    echo "   - For any prompt that has choices, you only need to enter the number (1, 2, 3, etc.) or the letter (a, b, c, etc.)."
    echo "   - For y/n prompts, enter 'y' for yes and 'n' for no."
    echo "   - For yes/no prompts, enter 'yes' for yes and 'no' for no."

    echo -e "${GREEN}3. Running Commands${RESET}"
    echo "   - After selecting an option, the script will execute the corresponding commands."
    echo "   - Ensure you have the necessary permissions and dependencies installed for the commands to run successfully."

    echo -e "${GREEN}4. Exiting the Script${RESET}"
    echo "   - To exit the script, select option 9 from the main menu."
    echo "   - Remember to run 'source ~/.bash_profile' after exiting to apply any changes made to environment variables."

    echo -e "${GREEN}5. Additional Tips${RESET}"
    echo "   - Always backup your wallets and important data before performing operations like deleting nodes."
    echo "   - Regularly update your nodes to the version tracked in VERSIONS.json to ensure compatibility and security."

    echo -e "${GREEN}6. Option Descriptions and Guides${RESET}"
    echo -e "${GREEN}Validator Node Options:${RESET}"
    echo "   a. Deploy/re-Deploy Validator Node: Install/reinstall the validator bundle tracked in VERSIONS.json."
    echo "   b. Manage Validator Node: Update version or perform maintenance."
    echo "   c. Apply Validator Node Snapshot: Speed up sync using official snapshot."
    echo "   d. Add Peers: Add peers (manual or Grand Valley preset)."
    echo "   e. Show Node Status: Display consensus and app status."
    echo "   f. Show Validator Node Logs: Tail both consensus and execution client logs."
    echo "   g. Show Consensus Client Logs: Tail only consensus logs."
    echo "   h. Show Execution Client Logs: Tail only Geth or Reth logs."
    echo "   i. Query Balance: Check EVM address balance via RPC."
    echo "   j. Create Validator: Submit create-validator tx (requires synced node and funds)."
    echo "   k. Delegate to Validator: Delegate OG to a validator."
    echo "   l. Undelegate from Validator: Undelegate previously delegated OG."
    echo "   m. Migrate Geth to Reth: Migrates your database from Geth to Reth."
    echo "   o. Check & Withdraw Rewards: Delegation value, commission, tip fees, and withdrawal queue."

    echo -e "${GREEN}Storage Node Options:${RESET}"
    echo "   a. Deploy Storage Node: Sets up a new storage node."
    echo "   b. Update Storage Node: Upgrades to the latest storage node version."
    echo "   c. Apply Storage Node Snapshot: Applies official snapshot for faster sync"
    echo -e "      - ${YELLOW}Important:${RESET} Always generate your own data_db - using others' will make you mine for them!"
    echo -e "      - Official docs: ${BLUE}https://docs.0g.ai/run-a-node/storage-node#snapshot${RESET}"
    echo "   d. Change Storage Node: Modifies storage node configuration."
    echo "   e. Show Storage Node Logs: Views storage node operational logs."
    echo "   f. Show Storage Node Status: Checks storage node health."

    echo -e "${GREEN}Storage KV Options:${RESET}"
    echo "   a. Deploy Storage KV: Sets up a key-value storage node."
    echo "   b. Show Storage KV Logs: Views KV node operational logs."
    echo "   c. Update Storage KV: Upgrades the KV node version."
 
    echo -e "${GREEN}AI Alignment Node Options:${RESET}"
    echo "   a. Run AI Alignment Node: Start AI Alignment Node (experimental)."
    echo "   b. Show AI Alignment Node Logs: View logs."
    echo "   c. Approve AI Alignment Delegations: Bulk registerOperator helper."
 
    echo -e "${GREEN}Node Management:${RESET}"
    echo "   a. Restart Validator Node"
    echo "   b. Restart Storage Node"
    echo "   c. Restart Storage KV"
    echo "   d. Restart AI Alignment Node"
    echo "   e. Stop Validator Node"
    echo "   f. Stop Storage Node"
    echo "   g. Stop Storage KV"
    echo "   h. Stop AI Alignment Node"
    echo "   i. Delete Validator Node (BACKUP your seed phrase/EVM private key and priv_validator_key.json)"
    echo "   j. Delete Storage Node"
    echo "   k. Delete Storage KV"
    echo "   l. Delete AI Alignment Node"
 
    echo -e "${GREEN}Utilities:${RESET}"
    echo "   6. Install 0gchain App: Installs the tracked CLI for transactions without running a node."
    echo "   7. Show Endpoints: Displays Grand Valley's public endpoints."
    echo "   8. Show Guidelines: Displays this help information."
 
    echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

# Menu function
function menu() {
    realtime_block_height=$(curl -s --connect-timeout 3 --max-time 10 -X POST "https://evmrpc.0g.ai" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result' | xargs printf "%d\n" 2>/dev/null || true)
    [ -z "$realtime_block_height" ] && realtime_block_height="N/A"
    local_rpc_port=$(grep -oP 'laddr = "tcp://(0.0.0.0|127.0.0.1):\K[0-9]+57' "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml" 2>/dev/null || echo "26657")
    local_node_height=$(curl -s --connect-timeout 1 --max-time 3 "http://127.0.0.1:$local_rpc_port/status" 2>/dev/null | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)
    [ -z "$local_node_height" ] && local_node_height="N/A (node not running)"
    block_difference="N/A"
    if [[ "$realtime_block_height" =~ ^[0-9]+$ && "$local_node_height" =~ ^[0-9]+$ ]]; then
        block_difference=$(( realtime_block_height - local_node_height ))
    fi
    echo -e "${ORANGE}Valley of 0G Mainnet${RESET}"
    echo "Main Menu:"
    echo -e "${GREEN}1. Validator Node${RESET}"
    echo "    a. Deploy/re-Deploy Validator Node"
    echo "    b. Manage Validator Node"
    echo "    c. Apply Validator Node Snapshot"
    echo "    d. Add Peers"
    echo "    e. Show Node Status"
    echo "    f. Show Validator Node Logs (Consensus + Execution Client)"
    echo "    g. Show Consensus Client Logs"
    echo "    h. Show Execution Client Logs (Geth or Reth)"
    echo "    i. Query Balance"
    echo "    j. Create Validator"
    echo "    k. Delegate to Validator"
    echo "    l. Undelegate from Validator"
    echo "    m. Migrate Geth to Reth (Experimental)"
    echo "    n. Rollback & Align CL/EL Height (Recovery)"
    echo "    o. Check & Withdraw Rewards (Delegation / Commission / Tip Fees)"
    echo -e "${GREEN}2. Storage Node${RESET}"
    echo "    a. Deploy Storage Node"
    echo "    b. Update Storage Node"
    echo "    c. Apply Storage Node Snapshot (Updated every 03.00 UTC)"
    echo "    d. Change Storage Node"
    echo "    e. Show Storage Node Logs"
    echo "    f. Show Storage Node Status"
    echo -e "${GREEN}3. Storage KV${RESET}"
    echo "    a. Deploy Storage KV"
    echo "    b. Show Storage KV Logs"
    echo "    c. Update Storage KV"
    echo -e "${GREEN}4. AI Alignment Node${RESET}"
    echo "    a. Run AI Alignment Node"
    echo "    b. Show AI Alignment Node Logs"
    echo "    c. Approve AI Alignment Delegations (bulk registerOperator)"
    echo -e "${GREEN}5. Node Management:${RESET}"
    echo "    a. Restart Validator Node"
    echo "    b. Restart Storage Node"
    echo "    c. Restart Storage KV"
    echo "    d. Restart AI Alignment Node"
    echo "    e. Stop Validator Node"
    echo "    f. Stop Storage Node"
    echo "    g. Stop Storage KV"
    echo "    h. Stop AI Alignment Node"
    echo "    i. Delete Validator Node (BACKUP YOUR SEEDS PHRASE/EVM-PRIVATE KEY AND priv_validator_key.json BEFORE YOU DO THIS)"
    echo "    j. Delete Storage Node"
    echo "    k. Delete Storage KV"
    echo "    l. Delete AI Alignment Node"
    echo "    m. Schedule Stop/Restart Validator Node"
    echo -e "${GREEN}6. Install the tracked 0gchain App only to execute transactions without running a node${RESET}"
    echo -e "${GREEN}7. Show Grand Valley's Endpoints${RESET}"
    echo -e "${YELLOW}8. Show Guidelines${RESET}"
    echo -e "${RED}9. Exit${RESET}"

    echo -e "Network Latest Block Height: ${GREEN}$realtime_block_height${RESET}"
    echo -e "Local Node Block Height: ${GREEN}$local_node_height${RESET}"
    echo -e "Block Difference: ${YELLOW}$block_difference${RESET}"
    echo -e "\n${YELLOW}Please run the following command to apply the changes after exiting the script:${RESET}"
    echo -e "${GREEN}source ~/.bash_profile${RESET}"
    echo -e "${YELLOW}This ensures the environment variables are set in your current bash session.${RESET}"
    echo -e "Stake your 0G with Grand Valley: ${ORANGE}https://explorer.0g.ai/mainnet/validators/0x108e619da0cdba8a301a53948a4acc23a3d79377/delegators${RESET}"
    echo -e "${GREEN}Let's Buidl 0G Together - Grand Valley${RESET}"
    read -p "Choose an option (e.g., 1a or 1 then a): " OPTION

    # Accept combined selections up to 9 and sub-letters up to 'o' (for Validator Node rewards option)
    if [[ $OPTION =~ ^[1-9][a-o]$ ]]; then
        MAIN_OPTION=${OPTION:0:1}
        SUB_OPTION=${OPTION:1:1}
    else
        MAIN_OPTION=$OPTION
        # If the selected main option is one that has sub-options (1..5), prompt for sub-option
        if [[ $MAIN_OPTION =~ ^[1-5]$ ]]; then
            read -p "Choose a sub-option: " SUB_OPTION
        fi
    fi

    case $MAIN_OPTION in
        1)
            case $SUB_OPTION in
                a) deploy_validator_node ;;
                b) manage_validator_node ;;
                c) apply_snapshot ;;
                d) add_peers ;;
                e) show_node_status ;;
                f) show_validator_logs ;;
                g) show_consensus_client_logs ;;
                h) show_geth_logs ;;
                i) query_balance ;;
                j) create_validator ;;
                k) delegate_to_validator ;;
                l) undelegate_from_validator ;;
                m) migrate_geth_to_reth ;;
                n) rollback_align_height ;;
                o) manage_staking_rewards ;;
                *) echo "Invalid sub-option. Please try again." ;;
            esac
            ;;
        2)
            case $SUB_OPTION in
                a) deploy_storage_node ;;
                b) update_storage_node ;;
                c) apply_storage_node_snapshot ;;
                d) change_storage_node ;;
                e) show_storage_logs ;;
                f) show_storage_status ;;
                *) echo "Invalid sub-option. Please try again." ;;
            esac
            ;;
        3)
            case $SUB_OPTION in
                a) deploy_storage_kv ;;
                b) show_storage_kv_logs ;;
                c) update_storage_kv ;;
                *) echo "Invalid sub-option. Please try again." ;;
            esac
            ;;
        4)
            case $SUB_OPTION in
                a) run_ai_alignment_node ;;
                b) show_ai_alignment_logs ;;
                c) approve_ai_alignment_node ;;
                *) echo "Invalid sub-option. Please try again." ;;
            esac
            ;;
        5)
            case $SUB_OPTION in
                a) restart_validator_node ;;
                b) restart_storage_node ;;
                c) restart_storage_kv ;;
                d) restart_ai_alignment_node ;;
                e) stop_validator_node ;;
                f) stop_storage_node ;;
                g) stop_storage_kv ;;
                h) stop_ai_alignment_node ;;
                i) delete_validator_node ;;
                j) delete_storage_node ;;
                k) delete_storage_kv ;;
                l) delete_ai_alignment_node ;;
                m) schedule_validator_node ;;
                *) echo "Invalid sub-option. Please try again." ;;
            esac
            ;;
        6) install_0gchain_app ;;
        7) show_endpoints ;;
        8) show_guidelines ;;
        9) exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
}

# Start menu
menu
