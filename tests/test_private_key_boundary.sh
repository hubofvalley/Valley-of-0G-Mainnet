#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MAIN="$ROOT/resources/valleyof0G.sh"
VALIDATOR_INSTALL="$ROOT/resources/0g_validator_node_aristotle_install.sh"
STORAGE_INSTALL="$ROOT/resources/0g_storage_node_install.sh"
STORAGE_UPDATE="$ROOT/resources/0g_storage_node_update.sh"
STORAGE_CHANGE="$ROOT/resources/0g_storage_node_change.sh"
ALIGNMENT="$ROOT/resources/0g_ai_alignment_node_install.sh"

fail() { echo "PRIVATE_KEY_BOUNDARY_TEST_FAIL: $*" >&2; exit 1; }

# EVM wallet signing must be handed directly to Foundry's native interactive
# signer prompt. Valley must not accept a raw key or pass it as argv.
grep -Fq -- '--interactive' "$MAIN" || fail "Foundry interactive signer is not used"
if grep -Fq -- '--private-key' "$MAIN"; then
    fail "main menu still places an EVM private key in argv"
fi
if grep -Eq '^[[:space:]]*read[^#\n]*(private key|PRIVATE_KEY)|^[[:space:]]*export[[:space:]]+PRIVATE_KEY=|^[[:space:]]*echo[[:space:]]+"?PRIVATE_KEY=' "$MAIN"; then
    fail "main menu still reads/exports/persists a wallet private key"
fi
if grep -Fq 'function ensure_private_key()' "$MAIN"; then
    fail "legacy private-key loader remains callable"
fi
grep -Fq 'Legacy PRIVATE_KEY entry detected' "$MAIN" || fail "legacy persistence warning is missing"

# A fresh deploy script must not silently destroy an existing consensus key or
# its last-sign state. The guard must inspect only file existence and execute
# before the destructive managed-data-root cleanup.
grep -Fq 'VALIDATOR_KEY_FILE="$HOME/.0gchaind/0g-home/0gchaind-home/config/priv_validator_key.json"' "$VALIDATOR_INSTALL" || fail "validator deploy does not track the managed consensus key path"
grep -Fq 'VALIDATOR_STATE_FILE="$HOME/.0gchaind/0g-home/0gchaind-home/data/priv_validator_state.json"' "$VALIDATOR_INSTALL" || fail "validator deploy does not track the managed signing-state path"
grep -Fq 'Baconvalley safety guard: existing validator signing material was detected.' "$VALIDATOR_INSTALL" || fail "validator deploy fail-closed guard is missing"
grep -Fq 'Do not run two active nodes with the same consensus key.' "$VALIDATOR_INSTALL" || fail "validator deploy double-sign safety warning is missing"

guard_line=$(grep -nF 'Baconvalley safety guard: existing validator signing material was detected.' "$VALIDATOR_INSTALL" | head -n1 | cut -d: -f1)
cleanup_line=$(grep -nF 'rm -rf $HOME/.0gchaind' "$VALIDATOR_INSTALL" | head -n1 | cut -d: -f1)
[[ "$guard_line" =~ ^[0-9]+$ && "$cleanup_line" =~ ^[0-9]+$ ]] || fail "cannot locate validator guard/cleanup ordering"
(( guard_line < cleanup_line )) || fail "validator signing-material guard runs after destructive cleanup"

# Menu UX remains present even where the unsafe automated signer path is now
# fail-safe/manual.
for label in \
    'j. Create Validator' \
    'k. Delegate to Validator' \
    'l. Undelegate from Validator' \
    'o. Check & Withdraw Rewards' \
    'a. Run AI Alignment Node' \
    'c. Approve AI Alignment Delegations'; do
    grep -Fq "$label" "$MAIN" || fail "menu label disappeared: $label"
done
grep -Fq 'Automated Alignment approval is disabled by the Valley private-key boundary.' "$MAIN" || fail "Alignment approval is not fail-safe"

# Fresh Storage install must not collect or emit a miner key. Update may detect
# the key field name only to preserve legacy config without reading the value.
if grep -Eq '^[[:space:]]*read[^#\n]*(private key|miner key)|--miner-key|miner_key[[:space:]]*=.*\$' "$STORAGE_INSTALL"; then
    fail "Storage installer handles raw miner-key material"
fi
if grep -Eq '^[[:space:]]*read[^#\n]*(private key|miner key)|--miner-key|miner_key[[:space:]]*=.*\$' "$STORAGE_UPDATE"; then
    fail "Storage updater handles raw miner-key material"
fi
if grep -Eq '^[[:space:]]*read[^#\n]*(private key|miner key)|--miner-key|miner_key[[:space:]]*=.*\$' "$STORAGE_CHANGE"; then
    fail "Storage config changer handles raw miner-key material"
fi
grep -Fq 'Service was NOT enabled or started' "$STORAGE_INSTALL" || fail "fresh Storage flow does not stop before secret-dependent startup"
grep -Fq 'Miner-key changes are intentionally not automated.' "$STORAGE_CHANGE" || fail "miner-key change is not fail-safe"

# Alignment release currently has no proven secure signer/secret interface.
# Managed flow must stage only and contain no raw-key field/argv/unit wiring.
if grep -Eq 'ZG_ALIGNMENT_NODE_SERVICE_PRIVATEKEY[[:space:]]*=|EnvironmentFile=|--key[[:space:]]+"?\$|^[[:space:]]*read[^#\n]*(private key|service key)' "$ALIGNMENT"; then
    fail "Alignment managed flow still carries raw key material"
fi
grep -Fq 'The service was NOT enabled or started' "$ALIGNMENT" || fail "Alignment installer does not fail safe before startup"
if grep -Eq 'systemctl[[:space:]]+(enable|start|restart)[[:space:]].*0g-alignment-node' "$ALIGNMENT"; then
    fail "Alignment installer starts/enables secret-dependent service"
fi

echo "PRIVATE_KEY_BOUNDARY_TEST_OK"
