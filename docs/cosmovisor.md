# Cosmovisor Guide

Cosmovisor manages planned `0gchaind` binary upgrades. It does not manage Geth or Reth.

## Prerequisites

- A healthy, fully synced validator or RPC node
- A tested backup of validator keys and configuration
- The upgrade name, height, binary, and checksum from an official 0G announcement
- Enough maintenance time to recover manually

## Migration

Launch Valley of 0G and select the Cosmovisor migration option:

```bash
bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Mainnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
```

Before confirming, inspect the generated service and directory layout. A normal layout contains:

```text
$HOME/.0gchaind/cosmovisor/
├── current -> upgrades/<name>
├── genesis/bin/0gchaind
└── upgrades/<name>/bin/0gchaind
```

## Verification

```bash
sudo systemctl cat 0gchaind
sudo systemctl status 0gchaind
sudo journalctl -u 0gchaind -n 100 --no-pager
readlink -f "$HOME/.0gchaind/cosmovisor/current"
```

Confirm `ExecStart` runs Cosmovisor, the current symlink resolves to the intended binary, the execution client remains healthy, and consensus height advances.

## Upgrade Safety

- Stage the exact binary before the upgrade height.
- Verify its checksum and executable permissions.
- Keep the previous binary available for a controlled rollback.
- Never infer an upgrade name or height from an old guide.
- Monitor both consensus and execution clients through the upgrade window.

If the chain halts, preserve logs and confirm the on-chain upgrade plan before changing symlinks or binaries.

last updated by: John
