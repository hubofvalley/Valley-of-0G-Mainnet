# Validator Node Guide

Deploy and operate the 0G Aristotle validator bundle with one consensus client and one execution client.

## Requirements

| Category | Requirement |
|---|---|
| CPU | 8 cores |
| RAM | 64+ GB |
| Storage | 1+ TB NVMe SSD |
| Bandwidth | 100 Mbps |
| OS | Ubuntu 22.04 or 24.04 |

Creating a validator requires at least 500 OG plus transaction gas. Keep additional capacity for database growth and snapshot extraction.

## Installation

Launch the menu:

```bash
bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Mainnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
```

Select **Validator Node** → **Deploy/re-Deploy Validator Node**, choose Geth or Reth, and follow the prompts.

The current bundle and shipped component versions are recorded in [`../VERSIONS.json`](../VERSIONS.json). The bundle installs:

- `0gchaind` as the consensus client
- either `0g-geth` or `0g-reth` as the execution client
- `$HOME/.0gchaind` as the default data root
- `0gchaind.service` plus exactly one execution service

Never run Geth and Reth against the same node data at the same time.

## Default Ports

| Port | Purpose |
|---|---|
| 26656 | Consensus P2P |
| 26657 | Consensus RPC |
| 8545 | EVM JSON-RPC |
| 8546 | EVM WebSocket |

Custom port prefixes selected during installation change these values.

## Health Checks

Set the active execution service once:

```bash
EL_SERVICE=0g-reth   # use 0g-geth when Geth is active
sudo systemctl status 0gchaind "$EL_SERVICE"
sudo journalctl -u 0gchaind -n 100 --no-pager
sudo journalctl -u "$EL_SERVICE" -n 100 --no-pager
curl -s http://127.0.0.1:26657/status | jq '.result.sync_info'
curl -s -X POST http://127.0.0.1:8545 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq
```

The consensus and execution heights must advance, both services must remain active, and the execution RPC must answer before validator creation.

## Service Operations

```bash
EL_SERVICE=0g-reth   # or 0g-geth

sudo systemctl restart 0gchaind "$EL_SERVICE"
sudo systemctl stop 0gchaind "$EL_SERVICE"
sudo journalctl -u "$EL_SERVICE" -f
```

Stopping either layer stops a healthy validator stack. Schedule maintenance deliberately and confirm recovery afterward.

## Creating a Validator

After both layers are fully synced:

1. Back up the validator key and wallet metadata offline.
2. Confirm the wallet contains at least 500 OG plus gas.
3. Open **Validator Node** → **Create Validator**.
4. Review moniker, commission, validator address, amount, and gas before confirming.
5. Confirm the validator appears on-chain and begins signing.

## Updates, Migration, and Rollback

- **Manual bundle update:** use **Manage Validator Node** → **Update Validator Node Version**.
- **Cosmovisor:** follow [Cosmovisor Setup](cosmovisor.md).
- **Geth to Reth:** use the migration option only after checking disk space and backing up configuration. Do not delete the Geth data until Reth is synced and stable.
- **CL/EL rollback alignment:** this is destructive maintenance. Record both heights, stop both services, preserve validator keys, and keep a recoverable data backup before proceeding.

Test update and rollback procedures on a non-validator or staging node first.

## Troubleshooting

- **Consensus not syncing:** inspect `net_info`, peers, disk latency, free space, and clock synchronisation.
- **Execution RPC unavailable:** confirm the selected execution service and its configured RPC port.
- **Height mismatch:** do not restart repeatedly. Compare consensus and execution logs and use the alignment workflow only when the failure is understood.
- **Missed blocks:** verify both services, NTP, peer count, disk I/O, and validator signing state.

## Related Documentation

- [Cosmovisor Setup](cosmovisor.md)
- [Snapshot Application](snapshots.md)
- [Node Scheduler](scheduler.md)

last updated by: John
