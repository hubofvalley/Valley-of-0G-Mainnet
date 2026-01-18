# Storage Node Guide

Deploy and manage a 0G storage node for the decentralized storage network.

## Overview

Storage nodes provide data availability and storage services for the 0G network. They store and serve data shards, earning rewards for their participation.

## System Requirements

| Category | Requirements |
|----------|--------------|
| CPU | 8+ cores |
| RAM | 32+ GB |
| Storage | 500GB - 1TB NVMe SSD |
| Bandwidth | 100 MBps |

## Installation

1. Launch Valley of 0G:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Mainnet/main/resources/valleyof0G.sh)
   ```
2. Select **"Storage Node"** → **"Deploy Storage Node"**
3. Follow the interactive prompts

**Current Version**: v1.1.0

## Configuration

The storage node connects to the 0G network to:
- Store data shards
- Respond to data availability queries
- Participate in the storage network protocol

## Updating

1. Launch Valley of 0G
2. Select **"Storage Node"** → **"Update Storage Node"**

## Configuration Changes

1. Launch Valley of 0G
2. Select **"Storage Node"** → **"Change Storage Node Config"**

## Snapshot Options

1. Launch Valley of 0G
2. Select **"Storage Node"** → **"Apply Snapshot"**
3. Choose between **Standard** or **Turbo** snapshot

## Related Documentation

- [Storage KV Guide](storage-kv.md)
- [Snapshot Application](snapshots.md)
