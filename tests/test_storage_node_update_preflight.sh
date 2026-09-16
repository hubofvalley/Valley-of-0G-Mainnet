#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPDATER="$ROOT/resources/0g_storage_node_update.sh"
TARGET_COMMIT='0445ef6a3a403468f14a4ce654bc2ecb0cfe9acc'

fail() { echo "STORAGE_NODE_UPDATE_PREFLIGHT_TEST_FAIL: $*" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/node/.git" "$TMP/node/run"

cat > "$TMP/manifest.sh" <<EOF
valley_manifest_init() { :; }
valley_manifest_get() {
    case "\$1" in
        '.components.storage_node.version_current') printf '%s\n' 'v1.2.0' ;;
        '.components.storage_node.pinned_commit') printf '%s\n' '$TARGET_COMMIT' ;;
        *) return 1 ;;
    esac
}
valley_require_git_commit() { return 0; }
EOF

cat > "$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >> "$MOCK_LOG"
if [[ "${1:-}" == rev-parse && "${2:-}" == HEAD ]]; then
    printf '%s\n' "$TARGET_COMMIT"
fi
EOF
cat > "$TMP/bin/cargo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'cargo %s\n' "$*" >> "$MOCK_LOG"
EOF
cat > "$TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'systemctl %s\n' "$*" >> "$MOCK_LOG"
EOF
cat > "$TMP/bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "$@"
EOF
chmod +x "$TMP/bin/git" "$TMP/bin/cargo" "$TMP/bin/systemctl" "$TMP/bin/sudo"

run_case() {
    local name=$1 config=$2 expected_status=$3 expected_message=${4:-}
    local log="$TMP/${name}.log" out="$TMP/${name}.out"
    printf '%s\n' "$config" > "$TMP/node/run/config-mainnet.toml"
    : > "$log"

    set +e
    PATH="$TMP/bin:$PATH" \
    MOCK_LOG="$log" \
    TARGET_COMMIT="$TARGET_COMMIT" \
    VALLEY_MANIFEST_LIB="$TMP/manifest.sh" \
    ZGS_HOME="$TMP/node" \
        bash "$UPDATER" >"$out" 2>&1
    status=$?
    set -e

    [[ "$status" -eq "$expected_status" ]] || {
        cat "$out" >&2
        fail "$name exited $status, expected $expected_status"
    }
    if [[ -n "$expected_message" ]]; then
        grep -Fq "$expected_message" "$out" || {
            cat "$out" >&2
            fail "$name did not emit expected diagnostic"
        }
    fi
}

common='listen_address_grpc = "127.0.0.1:50051"'
miner_value='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
miner="miner_key = \"${miner_value}\""

run_case zero_with_key "${common}"$'\n'"${miner}"$'\n''miner_cpu_percentage = 0' 1 'silently disables PoRA mining'
[[ ! -s "$TMP/zero_with_key.log" ]] || fail "zero-CPU refusal must happen before git/build/service mutation"
if grep -Fq "$miner_value" "$TMP/zero_with_key.out"; then
    fail "zero-CPU refusal exposed miner_key material"
fi

run_case plus_zero_with_key "${common}"$'\n'"${miner}"$'\n''miner_cpu_percentage = +0' 1 'silently disables PoRA mining'
[[ ! -s "$TMP/plus_zero_with_key.log" ]] || fail "+0 refusal must happen before git/build/service mutation"

run_case hex_zero_with_key "${common}"$'\n'"${miner}"$'\n''miner_cpu_percentage = 0x0' 1 'silently disables PoRA mining'
[[ ! -s "$TMP/hex_zero_with_key.log" ]] || fail "0x0 refusal must happen before git/build/service mutation"

single_quoted_miner="miner_key = '${miner_value}'"
run_case single_quote_key_zero "${common}"$'\n'"${single_quoted_miner}"$'\n''miner_cpu_percentage = 0' 1 'silently disables PoRA mining'
[[ ! -s "$TMP/single_quote_key_zero.log" ]] || fail "single-quoted miner_key must not bypass zero-CPU refusal"

run_case zero_without_key "${common}"$'\n''miner_cpu_percentage = 0' 0
[[ -s "$TMP/zero_without_key.log" ]] || fail "non-mining config without miner_key should retain update compatibility"

run_case zero_with_empty_key "${common}"$'\n''miner_key = ""'$'\n''miner_cpu_percentage = 0' 0
[[ -s "$TMP/zero_with_empty_key.log" ]] || fail "empty miner_key should retain non-mining update compatibility"

run_case normal_miner "${common}"$'\n'"${miner}"$'\n''miner_cpu_percentage = 100' 0
[[ -s "$TMP/normal_miner.log" ]] || fail "valid mining config should retain update compatibility"

echo "STORAGE_NODE_UPDATE_PREFLIGHT_TEST_OK"
