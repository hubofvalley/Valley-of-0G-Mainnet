# Cosmovisor Guide

Set up Cosmovisor for automatic validator node upgrades.

## Overview

Cosmovisor is a process manager that handles binary upgrades for Cosmos SDK-based chains. It monitors for upgrade proposals and automatically swaps binaries when an upgrade height is reached.

## Benefits

- **Automatic upgrades** - No manual intervention required
- **Zero downtime** - Seamless binary swaps
- **Rollback support** - Backup previous versions

## Migration

Migrate an existing validator to Cosmovisor:

1. Launch Valley of 0G:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Mainnet/main/resources/valleyof0G.sh)
   ```
2. Select **"Validator Node"** → **"Migrate to Cosmovisor"**

## Cosmovisor Updates

1. Launch Valley of 0G
2. Select **"Validator Node"** → **"Update via Cosmovisor"**

## Directory Structure

After migration, your validator uses:

```
$HOME/.0gchain/cosmovisor/
├── current -> genesis (or upgrades/<name>)
├── genesis/
│   └── bin/
│       └── 0gchaind
├── upgrades/
│   └── <upgrade-name>/
│       └── bin/
│           └── 0gchaind
└── backup/
```

## Related Documentation

- [Validator Node Guide](validator-node.md)
