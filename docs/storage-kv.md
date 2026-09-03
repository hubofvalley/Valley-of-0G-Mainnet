# Storage KV Guide

Deploy and manage a 0G Storage KV service. A reachable, synced Storage node is required first.

## Requirements

| Category | Requirement |
|---|---|
| CPU | 8+ cores |
| RAM | 32+ GB |
| Storage | Sized for the KV streams maintained, plus growth headroom |

The tracked version and pinned commit are defined in [`../VERSIONS.json`](../VERSIONS.json).

The managed `v1.4.0` source also pins its annotated tag object, peeled commit, and Rust `1.75.0` toolchain. Builds use `cargo build --release --locked`, so `Cargo.lock` drift fails closed. Valley intentionally does not execute a remote Rust bootstrap script.

## Installation

```bash
bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Mainnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
```

Select **Storage KV** → **Deploy Storage KV**. The default installation uses:

- service: `zgskv.service`
- repository: `$HOME/0g-storage-kv`
- config: `$HOME/0g-storage-kv/run/config.toml`
- binary: `$HOME/0g-storage-kv/target/release/zgs_kv`
- default RPC listener: `127.0.0.1:6789` (public bind requires an explicit opt-in)

The configured Storage node URL and EVM RPC endpoint must be reachable from the KV host. The installer calls `eth_chainId` and refuses any RPC that is not 0G Mainnet chain ID `16661` before building or activating the service.

Fresh install is staged first: Valley verifies the reviewed tag object and peeled commit, builds with the pinned Rust toolchain, prepares and checks the config, and only then asks for the typed `ACTIVATE-ZGSKV` gate. If an existing checkout or service is detected, the fresh installer refuses to overwrite it and directs the operator to the updater.

Upstream `v1.5.1` remains `review_required`. Its release adds cold-start optimization but requires that monitored streams do not already exist before the configured start block, so Valley does not auto-promote it without a live compatibility/canary review.

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

The managed updater stages and builds the reviewed target while the existing service remains online, then requires the typed `UPDATE-ZGSKV` gate. It retains a binary/config backup and attempts rollback if the replacement service does not return active.

## Troubleshooting

- **Service restart loop:** inspect the first error after startup, not only the repeated systemd restart message.
- **No `tx_seq` progress:** verify the EVM RPC, Storage node URL, start block, and contract configuration.
- **Connection refused:** check the upstream Storage node service and firewall before changing KV settings.
- **Disk growth:** stop the service before database maintenance and retain a recoverable backup.

## Related Documentation

- [Storage Node Guide](storage-node.md)

last updated by: John
