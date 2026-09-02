#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DOCTOR="$ROOT/resources/0g_node_doctor.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

grep -Fq '"node_doctor": "resources/0g_node_doctor.sh"' "$ROOT/VERSIONS.json"
grep -Fq 'p) run_node_doctor' "$ROOT/resources/valleyof0G.sh"
grep -Fq 'p. Run Node Doctor (read-only health/readiness checks)' "$ROOT/resources/valleyof0G.sh"
test -x "$DOCTOR"

mkdir -p "$TMP/bin" "$TMP/data"

cat > "$TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != is-active ]]; then
    echo "unexpected mutating systemctl call" >&2
    exit 99
fi
case "${2:-}" in
    0gchaind) printf 'active\n' ;;
    0g-reth)
        if [[ "${DOCTOR_EL_FIXTURE:-reth}" == reth || "${DOCTOR_EL_FIXTURE:-reth}" == both ]]; then
            printf 'active\n'
        else
            printf 'inactive\n'
        fi
        ;;
    0g-geth)
        if [[ "${DOCTOR_EL_FIXTURE:-reth}" == geth || "${DOCTOR_EL_FIXTURE:-reth}" == both ]]; then
            printf 'active\n'
        else
            printf 'inactive\n'
        fi
        ;;
    *) printf 'inactive\n' ;;
esac
EOF

cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
payload=''
while (($#)); do
    case "$1" in
        --data) payload=${2:-}; shift 2 ;;
        *) shift ;;
    esac
done
method=$(jq -r '.method' <<<"$payload")
if [[ "${DOCTOR_FIXTURE:-healthy}" == bad && "$method" == eth_syncing ]]; then
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"startingBlock":"0x1","currentBlock":"0x10","highestBlock":"0x64"}}'
    exit 0
fi
case "$method" in
    status)
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        case "${DOCTOR_FIXTURE:-healthy}" in
            stale) now='2000-01-01T00:00:00Z' ;;
            future) now='2099-01-01T00:00:00Z' ;;
            network-mismatch) network='wrong-network' ;;
            *) network='0G-mainnet-aristotle' ;;
        esac
        height=100
        [[ "${DOCTOR_FIXTURE:-healthy}" == hexletters ]] && height=6844
        printf '{"result":{"node_info":{"network":"%s"},"sync_info":{"latest_block_height":"%s","latest_block_time":"%s","catching_up":false}}}\n' "${network:-0G-mainnet-aristotle}" "$height" "$now"
        ;;
    net_info) printf '%s\n' '{"result":{"n_peers":"8"}}' ;;
    eth_syncing) printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":false}' ;;
    eth_blockNumber)
        if [[ "${DOCTOR_FIXTURE:-healthy}" == hexletters ]]; then printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":"0x1abc"}'; else printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":"0x64"}'; fi
        ;;
    eth_chainId) printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":"0x4115"}' ;;
    net_peerCount) printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":"0x3"}' ;;
    *) printf '%s\n' '{}' ;;
esac
EOF

cat > "$TMP/bin/ss" <<'EOF'
#!/usr/bin/env bash
prefix=${DOCTOR_PORT_PREFIX:-26}
if [[ "${DOCTOR_FIXTURE:-healthy}" == public ]]; then
  printf '%s\n' \
    "LISTEN 0 128 127.0.0.1:${prefix}657 0.0.0.0:*" \
    "LISTEN 0 128 0.0.0.0:${prefix}545 0.0.0.0:*" \
    "LISTEN 0 128 127.0.0.1:${prefix}551 0.0.0.0:*"
else
  printf '%s\n' \
    "LISTEN 0 128 127.0.0.1:${prefix}657 0.0.0.0:*" \
    "LISTEN 0 128 127.0.0.1:${prefix}545 0.0.0.0:*" \
    "LISTEN 0 128 127.0.0.1:${prefix}551 0.0.0.0:*"
fi
EOF

cat > "$TMP/bin/0gchaind" <<'EOF'
#!/usr/bin/env bash
printf '0gchaind version e8e1071\n'
EOF
cat > "$TMP/bin/0g-reth" <<'EOF'
#!/usr/bin/env bash
printf 'reth version 1.8.1\n'
EOF
cat > "$TMP/bin/0g-geth" <<'EOF'
#!/usr/bin/env bash
printf 'geth version 1.15.11\n'
EOF
chmod +x "$TMP/bin"/*

common_env=(
    PATH="$TMP/bin:$PATH"
    HOME="$TMP"
    DOCTOR_DATA_DIR="$TMP/data"
    DOCTOR_NTP_SYNCED=true
)

healthy_json=$(env "${common_env[@]}" "$DOCTOR" --json)
echo "$healthy_json" | jq -e '
    .schema_version == 1 and .overall == "ready" and .ready == true and
    .components.consensus.role == "consensus_layer" and
    .components.execution.role == "execution_layer" and
    .components.execution.service == "0g-reth" and
    .components.execution.active == true and
    .components.execution.active_services == ["0g-reth"] and
    (.components.execution.chain_id | type) == "number" and
    (.joint.engine_api_port == 26551) and
    (any(.checks[]; .id == "engine_listener" and .critical == true))
' >/dev/null

geth_json=$(env "${common_env[@]}" DOCTOR_EL_FIXTURE=geth "$DOCTOR" --json)
echo "$geth_json" | jq -e '.overall == "ready" and .components.execution.service == "0g-geth"' >/dev/null

hex_json=$(env "${common_env[@]}" DOCTOR_FIXTURE=hexletters "$DOCTOR" --json)
echo "$hex_json" | jq -e '.overall == "ready" and .components.execution.head == 6844 and .joint.head_gap == 0' >/dev/null

prefix_json=$(env "${common_env[@]}" DOCTOR_PORT_PREFIX=28 "$DOCTOR" --json)
echo "$prefix_json" | jq -e '.overall == "ready" and .joint.engine_api_port == 28551' >/dev/null

public_json=$(env "${common_env[@]}" DOCTOR_FIXTURE=public "$DOCTOR" --json)
echo "$public_json" | jq -e 'any(.checks[]; .id == "rpc_exposure" and .status == "warn" and .critical == false)' >/dev/null

if env "${common_env[@]}" DOCTOR_EL_FIXTURE=both "$DOCTOR" --json >/dev/null; then
    echo "dual execution-client fixture unexpectedly passed" >&2
    exit 1
fi
both_json=$(env "${common_env[@]}" DOCTOR_EL_FIXTURE=both "$DOCTOR" --json || true)
echo "$both_json" | jq -e 'any(.checks[]; .id == "execution_service" and .status == "fail")' >/dev/null

if env "${common_env[@]}" DOCTOR_FIXTURE=bad "$DOCTOR" --json >/dev/null; then
    echo "bad fixture unexpectedly passed" >&2
    exit 1
fi
bad_json=$(env "${common_env[@]}" DOCTOR_FIXTURE=bad "$DOCTOR" --json || true)
echo "$bad_json" | jq -e '.overall == "unhealthy" and .ready == false and any(.checks[]; .id == "execution_sync" and .status == "fail")' >/dev/null

for fixture in stale future network-mismatch; do
    if env "${common_env[@]}" DOCTOR_FIXTURE="$fixture" "$DOCTOR" --json >/dev/null; then
        echo "$fixture fixture unexpectedly passed" >&2
        exit 1
    fi
done

if env "${common_env[@]}" DOCTOR_CL_RPC_PORT=not-a-port "$DOCTOR" --json >/dev/null 2>&1; then
    echo "invalid port fixture unexpectedly passed" >&2
    exit 1
fi

if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|enable|disable)|sudo[[:space:]]' "$DOCTOR"; then
    echo "Node Doctor contains a service mutation path" >&2
    exit 1
fi
if grep -Eq 'cat[[:space:]].*(jwt|priv_validator)|grep[[:space:]].*(jwt|priv_validator)' "$DOCTOR"; then
    echo "Node Doctor appears to read key/JWT contents" >&2
    exit 1
fi

echo "NODE_DOCTOR_TEST_OK"
