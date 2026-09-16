#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMPL_NAME="0g_validator_node_aristotle_install_impl.sh"
LOCAL_IMPL="$SCRIPT_DIR/$IMPL_NAME"
MANAGED_DATA_ROOT="$HOME/.0gchaind"
VALIDATOR_KEY_FILE="$MANAGED_DATA_ROOT/0g-home/0gchaind-home/config/priv_validator_key.json"
VALIDATOR_STATE_FILE="$MANAGED_DATA_ROOT/0g-home/0gchaind-home/data/priv_validator_state.json"

path_exists() {
    [[ -e "$1" || -L "$1" ]]
}

# This public deploy entrypoint is fresh-install only. The implementation later
# stops services, removes the managed data root, initializes a new consensus
# identity/state pair, and starts CL/EL. Refuse before node-type selection so an
# existing validator cannot bypass the guard by choosing RPC mode.
if path_exists "$VALIDATOR_KEY_FILE" || path_exists "$VALIDATOR_STATE_FILE"; then
    cat >&2 <<EOF
Baconvalley safety guard: existing validator signing material was detected.

This fresh deploy flow is destructive and will not replace an existing consensus
key or priv_validator_state.json. The guard runs before validator/RPC selection,
so changing deploy type cannot bypass it.

Use Manage Validator Node for reviewed bundle updates and the documented
execution-client migration flow for EL changes. Recovery or rebuild of an
existing validator identity requires preserving BOTH the consensus key and the
last-sign state and ensuring only one signer is active; this installer does not
automate that recovery.

Protected paths:
  $VALIDATOR_KEY_FILE
  $VALIDATOR_STATE_FILE
EOF
    exit 1
fi

if path_exists "$MANAGED_DATA_ROOT"; then
    cat >&2 <<EOF
Baconvalley safety guard: existing managed 0G node data was detected at:
  $MANAGED_DATA_ROOT

Deploy Validator Node is a fresh-install flow and will not delete or replace an
existing managed validator/RPC data root. Use the appropriate update, migration,
snapshot, or recovery workflow instead. If the old node is intentionally being
decommissioned for a brand-new identity, back it up and remove it explicitly as
a separate operator action before using this installer.
EOF
    exit 1
fi

# Repository tests exercise only this non-mutating preflight path.
if [[ "${VALLEY_TEST_ONLY_PREFLIGHT:-0}" == "1" ]]; then
    echo "Validator deploy preflight passed: managed data root is absent."
    exit 0
fi

# Local clones execute the sibling implementation directly. The remote menu
# transport downloads only the requested helper, so fetch the implementation
# from the same repository/source ref in that mode.
if [[ -r "$LOCAL_IMPL" ]]; then
    exec bash "$LOCAL_IMPL" "$@"
fi

command -v curl >/dev/null 2>&1 || {
    echo "Validator installer implementation unavailable: curl is required for remote mode." >&2
    exit 2
}

VALLEY_REPOSITORY="${VALLEY_REPOSITORY:-hubofvalley/Valley-of-0G-Mainnet}"
VALLEY_SOURCE_REF="${VALLEY_SOURCE_REF:-main}"
REMOTE_IMPL="https://raw.githubusercontent.com/${VALLEY_REPOSITORY}/${VALLEY_SOURCE_REF}/resources/${IMPL_NAME}"
TMP_IMPL=$(mktemp)
cleanup() { rm -f "$TMP_IMPL"; }
trap cleanup EXIT

if ! curl -fsSL "$REMOTE_IMPL" -o "$TMP_IMPL"; then
    echo "Validator installer implementation download failed; nothing was executed." >&2
    exit 2
fi

bash "$TMP_IMPL" "$@"
