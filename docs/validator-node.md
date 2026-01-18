# Validator Node Guide

Deploy and manage a 0G validator node on the Aristotle mainnet.

## Overview

A validator node participates in 0G's consensus mechanism by validating transactions and producing blocks. Running a validator requires:
- Meeting hardware requirements
- Staking at least 500 OG tokens
- Maintaining high uptime (~99%+)

## System Requirements

| Category | Requirements |
|----------|--------------|
| CPU | 8 cores |
| RAM | 64+ GB |
| Storage | 1+ TB NVMe SSD |
| Bandwidth | 100 MBps |
| OS | Ubuntu 22.04/24.04 (recommended) |

## Installation

### How to Install

1. Launch Valley of 0G:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Mainnet/main/resources/valleyof0G.sh)
   ```
2. Select **"Deploy Validator Node"** from the menu
3. Follow the interactive prompts

### What Gets Installed

- **0gchaind** - Consensus client (v1.0.3)
- **0g-geth** - Execution client
- Systemd services: `0gchaind.service`, `0g-geth.service`
- Data directory: `$HOME/.0gchaind`

### Port Configuration

Default ports (adjustable during install):

| Port | Service |
|------|---------|
| 26657 | RPC |
| 26656 | P2P |
| 8545 | EVM-RPC |
| 8546 | WebSocket |

## Creating a Validator

After your node is fully synced:

1. Ensure you have 500+ OG in your wallet (plus gas)
2. Run the main menu: `bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Mainnet/main/resources/valleyof0G.sh)`
3. Select "Create Validator"
4. Follow the prompts to configure:
   - Moniker (validator name)
   - Commission rate
   - Identity (Keybase)
   - Website, email, details

## Updating

### How to Update

1. Launch Valley of 0G:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Mainnet/main/resources/valleyof0G.sh)
   ```
2. Select **"Manage Validator Node"** → **"Update Validator Node Version"**

### Cosmovisor (Automatic)

See [cosmovisor.md](cosmovisor.md) for automated upgrade setup.

## Service Management

```bash
# Check status
sudo systemctl status 0gchaind 0g-geth

# View logs
sudo journalctl -u 0gchaind -f
sudo journalctl -u 0g-geth -f

# Restart services
sudo systemctl restart 0gchaind 0g-geth

# Stop services
sudo systemctl stop 0gchaind 0g-geth
```

## Delegation Operations

### Delegate to a Validator

Use the main menu or directly:
1. Specify validator address or pubkey
2. Enter delegation amount in OG
3. Confirm transaction

### Undelegate

1. Select undelegate option from menu
2. Enter shares or OG amount to withdraw
3. Pay the validator's withdrawal fee
4. Funds released after unbonding period

## Validator Responsibilities

- **Uptime**: Maintain 99%+ uptime to avoid slashing
- **Updates**: Keep node software current
- **Security**: Protect your keys and server
- **Backups**: Regular backups of keys and data

## Troubleshooting

### Node Not Syncing
- Check peer connectivity: `curl localhost:26657/net_info`
- Verify disk space and I/O performance
- Consider applying a snapshot

### Service Won't Start
- Check logs: `sudo journalctl -u 0gchaind -n 100`
- Verify configuration in `$HOME/.0gchaind/0g-home/0gchaind-home/config/`

### Missed Blocks
- Ensure clock is synchronized (use NTP)
- Check network latency to peers
- Verify sufficient resources

## Related Documentation

- [Cosmovisor Setup](cosmovisor.md)
- [Snapshot Application](snapshots.md)
- [Node Scheduler](scheduler.md)
