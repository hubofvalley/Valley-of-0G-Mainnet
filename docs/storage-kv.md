# Storage KV Guide

Deploy and manage a 0G Storage KV service. A reachable, synced Storage node is required first.

## Requirements

| Category | Requirement |
|---|---|
| CPU | 8+ cores |
| RAM | 32+ GB |
| Storage | Sized for the KV streams maintained, plus growth headroom |

The tracked version and pinned commit are defined in [`../VERSIONS.json`](../VERSIONS.json).

## Installation

```bash
bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Mainnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
```

Select **Storage KV** → **Deploy Storage KV**. The default installation uses:

- service: `zgskv.service`
- repository: `$HOME/0g-storage-kv`
- config: `$HOME/0g-storage-kv/run/config.toml`
- binary: `$HOME/0g-storage-kv/target/release/zgs_kv`
- default RPC listener: port `6789`

The configured Storage node URL and EVM RPC endpoint must be reachable from the KV host.

## Health Checks

```bash
sudo systemctl status zgskv
sudo journalctl -u zgskv -n 100 --no-pager
sudo ss -lntp | grep ':6789'
df -h "$HOME/0g-storage-kv"
```

Confirm the service remains active, `tx_seq` advances in logs, the RPC listener is present, and disk use is stable.

## Updating

Use **Storage KV** → **Update Storage KV**. Before updating:

1. Record the current commit and binary version.
2. Back up `run/config.toml`.
3. Confirm the configured Storage node is healthy.
4. After restart, verify service status, logs, listener, and `tx_seq`.

## Troubleshooting

- **Service restart loop:** inspect the first error after startup, not only the repeated systemd restart message.
- **No `tx_seq` progress:** verify the EVM RPC, Storage node URL, start block, and contract configuration.
- **Connection refused:** check the upstream Storage node service and firewall before changing KV settings.
- **Disk growth:** stop the service before database maintenance and retain a recoverable backup.

## Related Documentation

- [Storage Node Guide](storage-node.md)

last updated by: John
