# Storage Node Guide

Deploy and manage a 0G Storage node.

## Requirements

| Category | Requirement |
|---|---|
| CPU | 8+ cores |
| RAM | 32+ GB |
| Storage | 500 GB–1 TB NVMe SSD, plus growth headroom |
| Bandwidth | 100 Mbps |

The current tracked version is defined in [`../VERSIONS.json`](../VERSIONS.json).

## Installation

```bash
bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Mainnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
```

Select **Storage Node** → **Deploy Storage Node** and review every prompt. The default installation uses:

- service: `zgs.service`
- repository: `$HOME/0g-storage-node`
- config: `$HOME/0g-storage-node/run/config-mainnet.toml`
- binary: `$HOME/0g-storage-node/target/release/zgs_node`
- RPC listener: port `5678`
- admin listener: port `5679`, which should remain private

The installer needs an EVM RPC endpoint and a storage miner key. Do not expose the key in shell history, logs, screenshots, or support requests.

## Health Checks

```bash
sudo systemctl status zgs
sudo journalctl -u zgs -n 100 --no-pager
curl -s -X POST http://127.0.0.1:5678 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}' | jq
df -h "$HOME/0g-storage-node"
```

Confirm the service stays active, logs advance without repeated errors, the node reports a progressing sync state, and disk headroom remains healthy.

## Updating

Use **Storage Node** → **Update Storage Node**. Before updating:

1. Record the current binary version and Git commit.
2. Back up `run/config-mainnet.toml`.
3. Confirm enough disk space for a rebuild.
4. After restart, verify service status, logs, RPC response, and sync progress.

## Configuration Changes

Use **Storage Node** → **Change Storage Node Config**. Keep a copy of the previous config and change one setting at a time. Do not publish the admin port or private key.

## Snapshots

Use **Storage Node** → **Apply Snapshot**, then choose Standard or Turbo for the matching node configuration. Snapshot replacement is destructive; follow [Snapshot Application](snapshots.md) first.

## Recovery

If an update or config change fails:

1. Stop `zgs`.
2. Restore the saved config.
3. Return to the previously recorded commit and rebuild if the binary changed.
4. Start `zgs` and verify logs and RPC health.

Do not delete the old database until the replacement is proven healthy.

## Related Documentation

- [Storage KV Guide](storage-kv.md)
- [Snapshot Application](snapshots.md)

last updated by: John
