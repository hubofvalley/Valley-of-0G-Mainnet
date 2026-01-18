# Snapshot Guide

Speed up node synchronization using snapshots.

## Overview

Snapshots allow you to quickly sync your node by downloading a pre-synced database state instead of syncing from genesis.

## How to Apply Snapshots

1. Launch Valley of 0G:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Mainnet/main/resources/valleyof0G.sh)
   ```

2. Navigate to your node type and select the snapshot option:
   - **Validator Node**: Select **"Validator Node"** → **"Apply Snapshot"**
   - **Storage Node**: Select **"Storage Node"** → **"Apply Snapshot"** (choose Standard or Turbo)

## Important Notes

- **Stop services** before applying snapshots
- **Backup** your current data if needed
- Snapshots may be several hours behind tip
- Verify snapshot source integrity

## Related Documentation

- [Validator Node Guide](validator-node.md)
- [Storage Node Guide](storage-node.md)
