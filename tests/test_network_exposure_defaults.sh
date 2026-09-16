#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installer_wrapper="$repo_root/resources/0g_validator_node_aristotle_install.sh"
installer="$repo_root/resources/0g_validator_node_aristotle_install_impl.sh"
migration="$repo_root/resources/0g_geth_to_reth_migrate.sh"
storage_installer="$repo_root/resources/0g_storage_node_install.sh"
storage_updater="$repo_root/resources/0g_storage_node_update.sh"

require() {
  grep -Fq -- "$1" "$2" || {
    echo "Missing expected hardening setting in $2: $1" >&2
    exit 1
  }
}

# The public validator deploy entrypoint must fail closed on existing managed
# node data before it can dispatch to the implementation.
require 'MANAGED_DATA_ROOT="$HOME/.0gchaind"' "$installer_wrapper"
require 'existing managed 0G node data was detected' "$installer_wrapper"
require 'existing validator signing material was detected' "$installer_wrapper"

# The implementation must keep every sensitive service local without its
# explicit public-RPC choice. The Engine API has no public option.
require 'RETH_HTTP_ADDR="127.0.0.1"' "$installer"
require 'MONITORING_ADDR="127.0.0.1"' "$installer"
require 'AUTHRPC_ADDR="127.0.0.1"' "$installer"
require '--http.addr ${RETH_HTTP_ADDR}' "$installer"
require '--authrpc.addr ${AUTHRPC_ADDR}' "$installer"
require 'pprof_laddr = \"${MONITORING_ADDR}:${OG_PORT}060\"' "$installer"
require 'prometheus_listen_addr = \"${MONITORING_ADDR}:${OG_PORT}660\"' "$installer"

# Migration defaults to loopback, and exposing HTTP RPC is an environment
# opt-in. AuthRPC remains loopback-only in both generated unit paths.
require 'case "${EXPOSE_PUBLIC_RPC:-no}" in' "$migration"
require 'no|n)  RETH_HTTP_ADDR="127.0.0.1" ;;' "$migration"
require 'AUTHRPC_ADDR="127.0.0.1"' "$migration"
if [ "$(grep -Fc -- '--authrpc.addr ${AUTHRPC_ADDR}' "$migration")" -ne 2 ]; then
  echo "Migration must generate two loopback-only AuthRPC unit paths." >&2
  exit 1
fi

# Storage HTTP RPC is intentionally public, while admin RPC and gRPC must be
# explicit. Fresh installs default gRPC to loopback; existing-node updates fail
# closed if the old config relies on upstream's implicit 0.0.0.0:50051 default.
require 'listen_address = "0.0.0.0:5678"' "$storage_installer"
require 'listen_address_admin = "127.0.0.1:5679"' "$storage_installer"
require 'listen_address_grpc = "127.0.0.1:50051"' "$storage_installer"
require 'Storage update refused: listen_address_grpc is not explicitly configured.' "$storage_updater"
require 'Upstream defaults the missing setting to 0.0.0.0:50051.' "$storage_updater"

echo "Network exposure default checks passed."
