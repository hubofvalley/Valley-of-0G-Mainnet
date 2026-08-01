#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installer="$repo_root/resources/0g_validator_node_aristotle_install.sh"
migration="$repo_root/resources/0g_geth_to_reth_migrate.sh"

require() {
  grep -Fq -- "$1" "$2" || {
    echo "Missing expected hardening setting in $2: $1" >&2
    exit 1
  }
}

# The installer must keep every sensitive service local without its explicit
# public-RPC choice. The Engine API has no public option.
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

echo "Network exposure default checks passed."
