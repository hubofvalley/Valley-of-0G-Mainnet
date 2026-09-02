#!/usr/bin/env bash
set -euo pipefail

# Valley of 0G Node Doctor
# Read-only validator diagnostics. It never starts/stops services, changes
# configuration, reads key/JWT contents, or contacts a remote endpoint by
# default. Explicit DOCTOR_*_URL overrides are supported for controlled checks.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="${VALLEY_MANIFEST_PATH:-$ROOT/VERSIONS.json}"

CL_SERVICE="${DOCTOR_CL_SERVICE:-${OG_SERVICE_NAME:-0gchaind}}"
GETH_SERVICE="${DOCTOR_GETH_SERVICE:-${OG_GETH_SERVICE_NAME:-0g-geth}}"
RETH_SERVICE="${DOCTOR_RETH_SERVICE:-${OG_RETH_SERVICE_NAME:-0g-reth}}"
DATA_DIR="${DOCTOR_DATA_DIR:-${HOME}/.0gchaind}"
HEAD_LAG_LIMIT="${DOCTOR_HEAD_LAG_LIMIT:-5}"
MIN_FREE_PERCENT="${DOCTOR_MIN_FREE_PERCENT:-10}"
MAX_HEAD_AGE_SECONDS="${DOCTOR_MAX_HEAD_AGE_SECONDS:-300}"
EXPECTED_CL_NETWORK="${DOCTOR_EXPECTED_CL_NETWORK:-}"
CL_CONFIG="${DOCTOR_CL_CONFIG:-${HOME}/.0gchaind/0g-home/0gchaind-home/config/config.toml}"

# Valley's OG_PORT is a prefix, not a complete port. The shipped defaults are
# CL RPC 26657, EL HTTP RPC 26545, and Engine API 26551. Prefer an explicit
# override, then the live CL config, then OG_PORT, so custom prefixes work.
CL_RPC_PORT="${DOCTOR_CL_RPC_PORT:-}"
if [[ -z "$CL_RPC_PORT" && -f "$CL_CONFIG" ]]; then
    CL_RPC_PORT=$(grep -oP 'laddr = "tcp://(?:0.0.0.0|127.0.0.1):\K[0-9]+' "$CL_CONFIG" 2>/dev/null | head -n 1 || true)
fi
CL_RPC_PORT="${CL_RPC_PORT:-${OG_PORT:-26}657}"
PORT_PREFIX="${DOCTOR_PORT_PREFIX:-}"
if [[ -z "$PORT_PREFIX" && "$CL_RPC_PORT" =~ ^([0-9]+)657$ ]]; then
    PORT_PREFIX="${BASH_REMATCH[1]}"
fi
PORT_PREFIX="${PORT_PREFIX:-${OG_PORT:-26}}"
EL_RPC_PORT="${DOCTOR_EL_RPC_PORT:-${PORT_PREFIX}545}"
ENGINE_PORT="${DOCTOR_ENGINE_PORT:-${PORT_PREFIX}551}"
CL_RPC_URL="${DOCTOR_CL_RPC_URL:-http://127.0.0.1:${CL_RPC_PORT}}"
EL_RPC_URL="${DOCTOR_EL_RPC_URL:-http://127.0.0.1:${EL_RPC_PORT}}"

for port_value in "$CL_RPC_PORT" "$EL_RPC_PORT" "$ENGINE_PORT"; do
    if ! [[ "$port_value" =~ ^[0-9]+$ ]] || (( port_value < 1 || port_value > 65535 )); then
        echo "Node Doctor received an invalid port: $port_value" >&2
        exit 2
    fi
done
if ! [[ "$HEAD_LAG_LIMIT" =~ ^[0-9]+$ ]] || ! [[ "$MIN_FREE_PERCENT" =~ ^[0-9]+$ ]] || (( MIN_FREE_PERCENT > 100 )) ||
   ! [[ "$MAX_HEAD_AGE_SECONDS" =~ ^[0-9]+$ ]]; then
    echo "Node Doctor received invalid numeric thresholds." >&2
    exit 2
fi

SYSTEMCTL="${DOCTOR_SYSTEMCTL_BIN:-systemctl}"
CURL="${DOCTOR_CURL_BIN:-curl}"
SS="${DOCTOR_SS_BIN:-ss}"
DF="${DOCTOR_DF_BIN:-df}"
TIMEDATECTL="${DOCTOR_TIMEDATECTL_BIN:-timedatectl}"
JQ="${DOCTOR_JQ_BIN:-jq}"

FORMAT=text
case "${1:-}" in
    "") ;;
    --json|--format=json) FORMAT=json ;;
    --help|-h)
        cat <<'EOF'
Usage: 0g_node_doctor.sh [--json]

Read-only 0G validator diagnostics. The doctor discovers the active execution
client from systemd, then evaluates the consensus and execution layers as one
joint CL/EL stack. Exit status: 0 ready, 1 unhealthy/degraded, 2 usage or
dependency error.

Environment overrides are intended for alternate ports and deterministic tests:
DOCTOR_CL_SERVICE, DOCTOR_GETH_SERVICE, DOCTOR_RETH_SERVICE,
DOCTOR_CL_RPC_URL, DOCTOR_EL_RPC_URL, DOCTOR_CL_RPC_PORT, DOCTOR_EL_RPC_PORT,
DOCTOR_ENGINE_PORT, DOCTOR_PORT_PREFIX, DOCTOR_DATA_DIR,
DOCTOR_EXPECTED_CL_NETWORK, DOCTOR_MAX_HEAD_AGE_SECONDS.
EOF
        exit 0
        ;;
    *)
        echo "Usage: $0 [--json]" >&2
        exit 2
        ;;
esac

for required_cmd in "$JQ" "$CURL"; do
    if ! command -v "$required_cmd" >/dev/null 2>&1; then
        echo "Node Doctor requires '$required_cmd'." >&2
        exit 2
    fi
done

if ! "$JQ" -e . "$MANIFEST" >/dev/null 2>&1; then
    echo "Node Doctor cannot read a valid VERSIONS.json: $MANIFEST" >&2
    exit 2
fi

expected_chain_id=$("$JQ" -r '.chain.evm_chain_id // empty' "$MANIFEST")
manifest_cl_network=$("$JQ" -r '.chain.consensus_network // empty' "$MANIFEST")
expected_cl_version=$("$JQ" -r '.components.validator.bundle.ships["0gchaind"] // empty' "$MANIFEST")
expected_geth_version=$("$JQ" -r '.components.validator.bundle.ships.geth // empty' "$MANIFEST")
expected_reth_version=$("$JQ" -r '.components.validator.bundle.ships.reth // empty' "$MANIFEST")
if [[ -z "$expected_chain_id" || -z "$manifest_cl_network" || -z "$expected_cl_version" || -z "$expected_geth_version" || -z "$expected_reth_version" ]]; then
    echo "Node Doctor manifest is missing required validator identity/version fields: $MANIFEST" >&2
    exit 2
fi
EXPECTED_CL_NETWORK="${DOCTOR_EXPECTED_CL_NETWORK:-$manifest_cl_network}"

status_json='[]'
add_check() {
    local id=$1 status=$2 detail=$3 critical=${4:-false}
    status_json=$("$JQ" -c --arg id "$id" --arg status "$status" --arg detail "$detail" \
        --argjson critical "$critical" '. + [{id:$id,status:$status,detail:$detail,critical:$critical}]' <<<"$status_json")
}

rpc_call() {
    local url=$1 method=$2
    "$CURL" -sS --connect-timeout 2 --max-time 5 \
        -H 'Content-Type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":[],\"id\":1}" \
        "$url" 2>/dev/null || true
}

service_state() {
    local service=$1 output
    if ! command -v "$SYSTEMCTL" >/dev/null 2>&1; then
        printf '%s' unknown
        return
    fi
    output=$("$SYSTEMCTL" is-active "$service" 2>/dev/null || true)
    if [[ "$output" == active ]]; then
        printf '%s' true
    elif [[ -n "$output" ]]; then
        printf '%s' false
    else
        printf '%s' unknown
    fi
}

cl_status=$(rpc_call "$CL_RPC_URL" status)
cl_net_info=$(rpc_call "$CL_RPC_URL" net_info)
el_syncing_json=$(rpc_call "$EL_RPC_URL" eth_syncing)
el_block_json=$(rpc_call "$EL_RPC_URL" eth_blockNumber)
el_chain_json=$(rpc_call "$EL_RPC_URL" eth_chainId)
el_peer_json=$(rpc_call "$EL_RPC_URL" net_peerCount)

cl_active=$(service_state "$CL_SERVICE")
geth_active=$(service_state "$GETH_SERVICE")
reth_active=$(service_state "$RETH_SERVICE")

if [[ "$cl_active" == true ]]; then
    add_check consensus_service pass "$CL_SERVICE active" true
elif [[ "$cl_active" == unknown ]]; then
    add_check consensus_service warn "cannot query $CL_SERVICE with systemctl" true
else
    add_check consensus_service fail "$CL_SERVICE is not active" true
fi

active_el_count=0
active_el_kind=unknown
active_el_service=unknown
[[ "$geth_active" == true ]] && { active_el_count=$((active_el_count + 1)); active_el_kind=geth; active_el_service="$GETH_SERVICE"; }
[[ "$reth_active" == true ]] && { active_el_count=$((active_el_count + 1)); active_el_kind=reth; active_el_service="$RETH_SERVICE"; }
if (( active_el_count == 1 )); then
    add_check execution_service pass "$active_el_kind service active" true
elif (( active_el_count > 1 )); then
    active_el_kind=unknown
    active_el_service=unknown
    add_check execution_service fail "both Geth and Reth services are active" true
elif [[ "$geth_active" == unknown || "$reth_active" == unknown ]]; then
    add_check execution_service warn "cannot determine active execution service" true
else
    add_check execution_service fail "neither Geth nor Reth service is active" true
fi

cl_rpc_ok=false
if "$JQ" -e '.result.sync_info' <<<"$cl_status" >/dev/null 2>&1; then
    cl_rpc_ok=true
    add_check consensus_rpc pass "$CL_RPC_URL responded" true
else
    add_check consensus_rpc fail "no valid CometBFT status from $CL_RPC_URL" true
fi

el_rpc_ok=false
if "$JQ" -e 'has("result")' <<<"$el_syncing_json" >/dev/null 2>&1; then
    el_rpc_ok=true
    add_check execution_rpc pass "$EL_RPC_URL responded" true
else
    add_check execution_rpc fail "no valid JSON-RPC response from $EL_RPC_URL" true
fi

cl_catching_up=unknown
cl_head=unknown
cl_network=unknown
cl_head_time=unknown
cl_peers=unknown
if [[ "$cl_rpc_ok" == true ]]; then
    cl_catching_up=$("$JQ" -r 'if .result.sync_info.catching_up == false or .result.sync_info.catching_up == "false" then "false" elif .result.sync_info.catching_up == true or .result.sync_info.catching_up == "true" then "true" else "unknown" end' <<<"$cl_status")
    cl_head=$("$JQ" -r '.result.sync_info.latest_block_height // "unknown"' <<<"$cl_status")
    cl_network=$("$JQ" -r '.result.node_info.network // "unknown"' <<<"$cl_status")
    cl_head_time=$("$JQ" -r '.result.sync_info.latest_block_time // "unknown"' <<<"$cl_status")
    cl_peers=$("$JQ" -r '.result.n_peers // "unknown"' <<<"$cl_net_info" 2>/dev/null || printf '%s' unknown)
fi
if [[ "$cl_catching_up" == false ]]; then
    add_check consensus_sync pass "catching_up=false" true
elif [[ "$cl_catching_up" == true ]]; then
    add_check consensus_sync fail "consensus client is still catching up" true
else
    add_check consensus_sync warn "consensus sync state unavailable" true
fi

if [[ -n "$EXPECTED_CL_NETWORK" ]]; then
    if [[ "$cl_network" == "$EXPECTED_CL_NETWORK" ]]; then
        add_check consensus_network pass "network ${cl_network}" true
    elif [[ "$cl_network" == unknown ]]; then
        add_check consensus_network warn "consensus network unavailable; expected ${EXPECTED_CL_NETWORK}" true
    else
        add_check consensus_network fail "network ${cl_network}, expected ${EXPECTED_CL_NETWORK}" true
    fi
else
    add_check consensus_network pass "network ${cl_network} (no expected value configured)" false
fi

cl_head_age=unknown
if [[ "$cl_head_time" != unknown ]] && command -v date >/dev/null 2>&1; then
    head_epoch=$(date -u -d "$cl_head_time" +%s 2>/dev/null || true)
    now_epoch=$(date -u +%s 2>/dev/null || true)
    if [[ "$head_epoch" =~ ^[0-9]+$ && "$now_epoch" =~ ^[0-9]+$ ]]; then
        cl_head_age=$((now_epoch - head_epoch))
    fi
fi
if [[ "$cl_head_age" =~ ^[0-9]+$ ]]; then
    if (( cl_head_age <= MAX_HEAD_AGE_SECONDS )); then
        add_check consensus_head_freshness pass "latest block age=${cl_head_age}s (limit ${MAX_HEAD_AGE_SECONDS}s)" true
    else
        add_check consensus_head_freshness fail "latest block age=${cl_head_age}s exceeds ${MAX_HEAD_AGE_SECONDS}s" true
    fi
elif [[ "$cl_head_age" =~ ^- ]]; then
    add_check consensus_head_freshness fail "latest block timestamp is in the future" true
    cl_head_age=unknown
else
    add_check consensus_head_freshness warn "latest block timestamp unavailable" true
fi

el_sync=unknown
el_head=unknown
el_head_decimal=unknown
el_chain_id=unknown
el_peers=unknown
if [[ "$el_rpc_ok" == true ]]; then
    el_sync=$("$JQ" -r 'if .result == false then "false" elif .result == null then "unknown" else "true" end' <<<"$el_syncing_json")
    el_head=$("$JQ" -r '.result // "unknown"' <<<"$el_block_json")
    if [[ "$el_head" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
        el_head_decimal=$((16#${el_head:2}))
    elif [[ "$el_head" =~ ^[0-9]+$ ]]; then
        el_head_decimal=$el_head
    fi
    el_chain_hex=$("$JQ" -r '.result // ""' <<<"$el_chain_json")
    if [[ "$el_chain_hex" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
        el_chain_id=$((16#${el_chain_hex:2}))
    elif [[ "$el_chain_hex" =~ ^[0-9]+$ ]]; then
        el_chain_id=$el_chain_hex
    fi
    el_peers_hex=$("$JQ" -r '.result // ""' <<<"$el_peer_json")
    if [[ "$el_peers_hex" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
        el_peers=$((16#${el_peers_hex:2}))
    elif [[ "$el_peers_hex" =~ ^[0-9]+$ ]]; then
        el_peers=$el_peers_hex
    fi
fi
if [[ "$el_sync" == false ]]; then
    add_check execution_sync pass "eth_syncing=false" true
elif [[ "$el_sync" == true ]]; then
    add_check execution_sync fail "execution client is still syncing" true
else
    add_check execution_sync warn "execution sync state unavailable" true
fi

head_gap=unknown
if [[ "$cl_head" =~ ^[0-9]+$ && "$el_head" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
    el_head_decimal=$((16#${el_head:2}))
    head_gap=$((cl_head - el_head_decimal))
elif [[ "$cl_head" =~ ^[0-9]+$ && "$el_head" =~ ^[0-9]+$ ]]; then
    head_gap=$((cl_head - el_head))
fi
if [[ "$head_gap" =~ ^-?[0-9]+$ ]]; then
    abs_gap=${head_gap#-}
    if (( abs_gap <= HEAD_LAG_LIMIT )); then
        add_check cl_el_head pass "CL/EL head gap=${head_gap} (limit ${HEAD_LAG_LIMIT})" true
    else
        add_check cl_el_head fail "CL/EL head gap=${head_gap} exceeds ${HEAD_LAG_LIMIT}" true
    fi
else
    add_check cl_el_head warn "CL/EL heads unavailable" true
fi

if [[ "$el_chain_id" == "$expected_chain_id" ]]; then
    add_check chain_id pass "EVM chain ID ${el_chain_id}" true
elif [[ "$el_chain_id" == unknown ]]; then
    add_check chain_id warn "EVM chain ID unavailable" true
else
    add_check chain_id fail "EVM chain ID ${el_chain_id}, expected ${expected_chain_id}" true
fi

binary_version() {
    local binary=$1 output
    if [[ -n "$binary" && -x "$binary" ]]; then
        output=$("$binary" --version 2>/dev/null || true)
        [[ -z "$output" ]] && output=$("$binary" version 2>/dev/null || true)
        printf '%s' "${output//$'\n'/ }"
    else
        printf '%s' unknown
    fi
}

cl_binary="${DOCTOR_CL_BINARY:-$(command -v 0gchaind 2>/dev/null || true)}"
geth_binary="${DOCTOR_GETH_BINARY:-$(command -v 0g-geth 2>/dev/null || true)}"
reth_binary="${DOCTOR_RETH_BINARY:-$(command -v 0g-reth 2>/dev/null || true)}"
cl_version="${DOCTOR_CL_VERSION:-$(binary_version "$cl_binary")}" 
if [[ "$active_el_kind" == reth ]]; then
    el_version="${DOCTOR_EL_VERSION:-$(binary_version "$reth_binary")}" 
    expected_el_version=$expected_reth_version
else
    el_version="${DOCTOR_EL_VERSION:-$(binary_version "$geth_binary")}" 
    expected_el_version=$expected_geth_version
fi
version_matches() {
    local observed=$1 expected=$2 expected_re
    expected_re=${expected//./\\.}
    [[ "$observed" =~ (^|[^[:alnum:]])${expected_re}([^[:alnum:]]|$) ]]
}
if [[ "$cl_version" != unknown ]] && version_matches "$cl_version" "$expected_cl_version"; then
    add_check consensus_version pass "${cl_version}" false
elif [[ "$cl_version" == unknown ]]; then
    add_check consensus_version warn "0gchaind version unavailable" false
else
    add_check consensus_version fail "observed ${cl_version}; expected ${expected_cl_version}" false
fi
if [[ "$el_version" != unknown ]] && version_matches "$el_version" "$expected_el_version"; then
    add_check execution_version pass "${el_version}" false
elif [[ "$el_version" == unknown ]]; then
    add_check execution_version warn "${active_el_kind} version unavailable" false
else
    add_check execution_version fail "observed ${el_version}; expected ${expected_el_version}" false
fi

listeners_for_port() {
    local port=$1
    if ! command -v "$SS" >/dev/null 2>&1; then
        printf '%s' unknown
        return
    fi
    "$SS" -H -ltn 2>/dev/null | awk -v port=":${port}" '$4 ~ port "$" { print $4; found=1 } END { if (!found) exit 1 }' | paste -sd, - || true
}
engine_listener=$(listeners_for_port "$ENGINE_PORT")
if [[ -n "$engine_listener" && "$engine_listener" != unknown ]]; then
    add_check engine_listener pass "TCP listener ${engine_listener} (port ${ENGINE_PORT}); authenticated Engine API not probed" true
elif [[ "$engine_listener" == unknown ]]; then
    add_check engine_listener warn "cannot inspect Engine API port ${ENGINE_PORT}; ss is unavailable" true
else
    add_check engine_listener fail "Engine API port ${ENGINE_PORT} is not listening" true
fi

listener_exposure() {
    local port=$1 listener
    listener=$(listeners_for_port "$port")
    if [[ -z "$listener" || "$listener" == unknown ]]; then
        printf '%s' unknown
    elif grep -Eq '(^|,)(0\.0\.0\.0|\[::\]|\*):' <<<"$listener"; then
        printf '%s' public
    else
        printf '%s' loopback_or_private
    fi
}
cl_exposure=$(listener_exposure "$CL_RPC_PORT")
el_exposure=$(listener_exposure "$EL_RPC_PORT")
if [[ "$cl_exposure" == public || "$el_exposure" == public ]]; then
    add_check rpc_exposure warn "RPC listener exposure: CL=${cl_exposure}, EL=${el_exposure}" false
elif [[ "$cl_exposure" == unknown || "$el_exposure" == unknown ]]; then
    add_check rpc_exposure warn "cannot inspect RPC listener exposure" false
else
    add_check rpc_exposure pass "RPC listeners are not detected as public" false
fi

disk_status=unknown
disk_detail="disk headroom unavailable"
if command -v "$DF" >/dev/null 2>&1; then
    disk_line=$("$DF" -Pk "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4, $5}' || true)
    free_kb=$(awk '{print $1}' <<<"$disk_line")
    used_percent=$(awk '{gsub(/%/, "", $2); print $2}' <<<"$disk_line")
    if [[ "$free_kb" =~ ^[0-9]+$ && "$used_percent" =~ ^[0-9]+$ ]]; then
        free_percent=$((100 - used_percent))
        disk_detail="${free_percent}% free (${free_kb} KiB)"
        if (( free_percent >= MIN_FREE_PERCENT )); then disk_status=pass; else disk_status=fail; fi
    fi
fi
[[ "$disk_status" == unknown ]] && disk_status=warn
add_check disk_headroom "$disk_status" "$disk_detail" false

ntp_status=unknown
if [[ -n "${DOCTOR_NTP_SYNCED:-}" ]]; then
    [[ "$DOCTOR_NTP_SYNCED" == true || "$DOCTOR_NTP_SYNCED" == yes ]] && ntp_status=pass || ntp_status=fail
elif command -v "$TIMEDATECTL" >/dev/null 2>&1; then
    ntp_value=$("$TIMEDATECTL" show --property=NTPSynchronized --value 2>/dev/null || true)
    [[ "$ntp_value" == yes ]] && ntp_status=pass
    [[ "$ntp_value" == no ]] && ntp_status=fail
fi
[[ "$ntp_status" == unknown ]] && ntp_status=warn
add_check clock_sync "$ntp_status" "NTP synchronisation: ${ntp_status}" false

critical_failures=$("$JQ" '[.[] | select(.critical == true and .status == "fail")] | length' <<<"$status_json")
critical_warnings=$("$JQ" '[.[] | select(.critical == true and .status == "warn")] | length' <<<"$status_json")
advisory_failures=$("$JQ" '[.[] | select(.critical == false and .status == "fail")] | length' <<<"$status_json")
advisory_warnings=$("$JQ" '[.[] | select(.critical == false and .status == "warn")] | length' <<<"$status_json")
if (( critical_failures == 0 && critical_warnings == 0 )); then
    ready=true
    overall=ready
elif (( critical_failures > 0 )); then
    ready=false
    overall=unhealthy
else
    ready=false
    overall=degraded
fi
el_active=false
if (( active_el_count == 1 )); then
    el_active=true
fi

result=$(
    "$JQ" -n \
        --argjson schema_version 1 \
        --arg overall "$overall" \
        --argjson ready "$ready" \
        --argjson checks "$status_json" \
        --arg cl_service "$CL_SERVICE" \
        --arg cl_role "consensus_layer" \
        --arg cl_active "$cl_active" \
        --arg cl_head "$cl_head" \
        --arg cl_catching_up "$cl_catching_up" \
        --arg cl_network "$cl_network" \
        --arg cl_head_time "$cl_head_time" \
        --arg cl_head_age "$cl_head_age" \
        --arg cl_peers "$cl_peers" \
        --arg cl_version "$cl_version" \
        --arg el_service "$active_el_service" \
        --arg el_role "execution_layer" \
        --arg el_active "$el_active" \
        --arg el_head "$el_head" \
        --arg el_head_decimal "$el_head_decimal" \
        --arg el_sync "$el_sync" \
        --arg el_chain_id "$el_chain_id" \
        --arg el_peers "$el_peers" \
        --arg el_version "$el_version" \
        --arg geth_service "$GETH_SERVICE" \
        --arg reth_service "$RETH_SERVICE" \
        --arg geth_active "$geth_active" \
        --arg reth_active "$reth_active" \
        --arg active_el_count "$active_el_count" \
        --arg engine_port "$ENGINE_PORT" \
        --arg head_gap "$head_gap" \
        --arg expected_chain_id "$expected_chain_id" \
        --arg critical_failures "$critical_failures" \
        --arg critical_warnings "$critical_warnings" \
        --arg advisory_failures "$advisory_failures" \
        --arg advisory_warnings "$advisory_warnings" \
        'def bool_value: if . == "true" then true elif . == "false" then false else null end;
         def num_value: if . == "unknown" or . == "" then null elif test("^-?[0-9]+$") then tonumber else null end;
         {schema_version:$schema_version,overall:$overall,ready:$ready,
          components:{consensus:{role:$cl_role,service:$cl_service,active:($cl_active|bool_value),
            head:($cl_head|num_value),catching_up:($cl_catching_up|bool_value),network:($cl_network|if .=="unknown" then null else . end),
            latest_block_time:($cl_head_time|if .=="unknown" then null else . end),latest_block_age_seconds:($cl_head_age|num_value),
            peers:($cl_peers|num_value),version:$cl_version},
            execution:{role:$el_role,service:(if $active_el_count == "1" then $el_service else null end),
            active:(if $active_el_count == "1" then true elif $active_el_count == "0" then false else null end),
            active_services:([if $geth_active == "true" then $geth_service else empty end,
                              if $reth_active == "true" then $reth_service else empty end]),
            head:($el_head_decimal|num_value),syncing:($el_sync|bool_value),
            chain_id:($el_chain_id|num_value),peers:($el_peers|num_value),version:$el_version}},
          joint:{head_gap:($head_gap|num_value),expected_chain_id:($expected_chain_id|num_value),engine_api_port:($engine_port|tonumber)},
          counts:{critical_failures:($critical_failures|tonumber),critical_warnings:($critical_warnings|tonumber),
                  advisory_failures:($advisory_failures|tonumber),advisory_warnings:($advisory_warnings|tonumber)},
          checks:$checks}'
)

if [[ "$FORMAT" == json ]]; then
    printf '%s\n' "$result"
else
    printf 'Valley of 0G Node Doctor — %s\n' "$overall"
    printf 'CL: 0gchaind (%s), head=%s, catching_up=%s, peers=%s\n' "$cl_active" "$cl_head" "$cl_catching_up" "$cl_peers"
    printf 'EL: %s (%s), head=%s, syncing=%s, peers=%s, chain_id=%s\n' "$active_el_kind" "$active_el_count" "$el_head" "$el_sync" "$el_peers" "$el_chain_id"
    printf 'Joint: head_gap=%s, Engine API port=%s\n\n' "$head_gap" "$ENGINE_PORT"
    "$JQ" -r '.checks[] | "[\(.status | ascii_upcase)] \(.id): \(.detail)"' <<<"$result"
    printf '\nRead-only check complete. No services or configuration were changed.\n'
fi

(( critical_failures == 0 && critical_warnings == 0 ))
