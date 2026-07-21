#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/resources/0g_geth_to_reth_migrate.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "not ok - $*" >&2; exit 1; }
contains() { grep -Fq "$2" "$1" || fail "$1 does not contain: $2"; }

make_fixture() {
    local root=$1
    mkdir -p "$root/home/go/bin" "$root/home/aristotle-used/bin" \
        "$root/home/.0gchaind/0g-home/geth-home" \
        "$root/home/.0gchaind/0g-home/0gchaind-home/config" "$root/bin"
    printf 'original-jwt\n' > "$root/home/.0gchaind/jwt.hex"
    printf 'geth-data\n' > "$root/home/.0gchaind/0g-home/geth-home/LOCK"
    printf 'cl-config\n' > "$root/home/.0gchaind/0g-home/0gchaind-home/config/app.toml"
    printf '{}\n' > "$root/home/aristotle-used/geth-genesis.json"
    printf 'new-jwt\n' > "$root/home/aristotle-used/jwt.hex"
    printf '{}\n' > "$root/home/aristotle-used/kzg-trusted-setup.json"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$root/home/aristotle-used/bin/0gchaind"
    cat > "$root/home/aristotle-used/bin/reth" <<'EOF'
#!/usr/bin/env bash
printf 'reth %s\n' "$*" >> "$CALL_LOG"
[ "${1:-}" = init ] || exit 90
while [ "$#" -gt 0 ]; do
    [ "$1" = --datadir ] && { shift; datadir=$1; }
    shift
done
mkdir -p "$datadir/db"
printf '[prune.segments.receipts_log_filter]\n' > "$datadir/reth.toml"
printf 'temporary-db\n' > "$datadir/db/marker"
EOF
    chmod +x "$root/home/aristotle-used/bin/reth" "$root/home/aristotle-used/bin/0gchaind"
    cp "$root/home/aristotle-used/bin/reth" "$root/home/go/bin/0g-reth"
    cat > "$root/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$CALL_LOG"
exec "$@"
EOF
    printf '#!/usr/bin/env bash\nprintf "203.0.113.10"\n' > "$root/bin/curl"
    chmod +x "$root/bin/sudo" "$root/bin/curl"
}

test_no_stages_without_migrating() {
    local root="$TMP/no" staging
    make_fixture "$root"
    : > "$root/calls"
    printf 'export IMPORT_GETH_DATA=yes\n' > "$root/home/.bash_profile"
    printf '\n\n' | env HOME="$root/home" USER=test PATH="$root/bin:$PATH" \
        CALL_LOG="$root/calls" OG_PORT=26 NODE_TYPE=rpc IMPORT_GETH_DATA=No \
        bash "$SCRIPT" > "$root/output" 2>&1 || fail "preparation-only run failed"

    staging="$root/home/.0gchaind/reth-migration-staging"
    [ -f "$staging/0g-reth.service.draft" ] || fail "draft unit was not staged"
    [ -f "$staging/reth.toml" ] || fail "reth.toml was not staged"
    [ -f "$staging/geth-genesis.json" ] || fail "genesis was not staged"
    [ -f "$staging/kzg-trusted-setup.json" ] || fail "KZG setup was not staged"
    [ -f "$staging/consensus-engine-url-change.txt" ] || fail "inactive CL instruction was not staged"
    contains "$staging/consensus-engine-url-change.txt" "Inactive intended change only; it has not been applied:"
    [ ! -e "$root/home/.0gchaind/0g-home/reth-home" ] || fail "live Reth home exists"

    [ "$(cat "$root/home/.0gchaind/jwt.hex")" = original-jwt ] || fail "JWT changed"
    [ "$(cat "$root/home/.0gchaind/0g-home/geth-home/LOCK")" = geth-data ] || fail "Geth changed"
    [ "$(cat "$root/home/.0gchaind/0g-home/0gchaind-home/config/app.toml")" = cl-config ] || fail "CL changed"
    ! grep -Eq 'systemctl| export( |$)| import( |$)|trim_export| node( |$)| start( |$)' "$root/calls" || fail "unsafe command ran"
    [ "$(grep -c '^reth init ' "$root/calls")" -eq 1 ] || fail "isolated init was not the only Reth operation"
    ! grep -Fq 'Do you want to proceed with migration?' "$root/output" || fail "no mode requested migration confirmation"

    printf '%s\n' \
        'Geth import skipped.' \
        'Reth database has not been populated.' \
        'Apply or restore the Reth database manually, then verify it before starting Reth and the consensus service.' \
        'The existing Geth datadir and service have been retained for rollback.' > "$root/expected"
    tail -n 4 "$root/output" > "$root/actual"
    cmp -s "$root/expected" "$root/actual" || fail "approved four-line checkpoint changed"
}

test_mode_selection() {
    local value output select_line confirm_line source_line
    for value in y Y yes YES Yes; do
        output=$(IMPORT_GETH_DATA="$value" MIGRATION_MODE_SELECTION_ONLY=1 bash "$SCRIPT" 2>&1)
        [ "${output##*$'\n'}" = yes ] || fail "$value did not map to yes"
    done
    for value in n N no NO No; do
        output=$(IMPORT_GETH_DATA="$value" MIGRATION_MODE_SELECTION_ONLY=1 bash "$SCRIPT" 2>&1)
        [ "${output##*$'\n'}" = no ] || fail "$value did not map to no"
    done
    output=$(printf '\n' | env -u IMPORT_GETH_DATA MIGRATION_MODE_SELECTION_ONLY=1 bash "$SCRIPT" 2>&1)
    [ "${output##*$'\n'}" = yes ] || fail "interactive default is not yes"
    output=$(printf 'invalid\nn\n' | env -u IMPORT_GETH_DATA MIGRATION_MODE_SELECTION_ONLY=1 bash "$SCRIPT" 2>&1)
    [[ "$output" == *"Please enter y or n."* ]] || fail "invalid interactive input was not rejected"
    [ "${output##*$'\n'}" = no ] || fail "reprompt did not accept no"
    if output=$(IMPORT_GETH_DATA=maybe MIGRATION_MODE_SELECTION_ONLY=1 bash "$SCRIPT" 2>&1); then
        fail "invalid environment value succeeded"
    fi
    [[ "$output" == *"Error: IMPORT_GETH_DATA must be y, yes, n, or no"* ]] || fail "invalid environment error is unclear"

    select_line=$(grep -n '^select_import_mode$' "$SCRIPT" | cut -d: -f1)
    confirm_line=$(grep -n 'Do you want to proceed with migration?' "$SCRIPT" | cut -d: -f1)
    source_line=$(grep -n '^source .*\.bash_profile' "$SCRIPT" | cut -d: -f1)
    [ "$select_line" -lt "$confirm_line" ] || fail "confirmation is before mode selection"
    [ "$confirm_line" -lt "$source_line" ] || fail "confirmation is after environment sourcing"
}

test_existing_jwt_copy_is_guarded() {
    awk '
        /if \[ ! -e "\$HOME\/\.0gchaind\/jwt\.hex" \]; then/ { guard_line = NR }
        /cp "\$HOME\/aristotle-used\/jwt\.hex" "\$HOME\/\.0gchaind\/jwt\.hex"/ {
            copy_count++
            if (guard_line == NR - 1) guarded_copy = 1
        }
        END { exit !(copy_count == 1 && guarded_copy) }
    ' "$SCRIPT" || fail "packaged JWT copy is not guarded by destination nonexistence"
}

test_no_stages_without_migrating
test_mode_selection
test_existing_jwt_copy_is_guarded
echo "ok - migration staging and mode safety"
