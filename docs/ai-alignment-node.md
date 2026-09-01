# AI Alignment Node Guide

Install and operate the 0G AI Alignment Node through Valley of 0G.

## Prerequisites

- A supported Linux host with sufficient CPU, memory, storage, and bandwidth for the selected workload
- A reachable 0G mainnet EVM RPC endpoint
- A funded operator wallet when on-chain approval or delegation is required
- Backups of configuration and operator metadata

The tracked release is defined in [`../VERSIONS.json`](../VERSIONS.json).

## Installation

```bash
bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Mainnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
```

Select **AI Alignment Node** → **Run AI Alignment Node**. Valley verifies the release artifact from `VERSIONS.json`, stages the binary and non-secret configuration, and can stage a disabled service unit.

## Private-key boundary

The official Alignment v1.0.0 release surface requires raw service private-key material in environment/configuration and exposes a raw `--key` signing path for registration and approval. Valley does not collect, persist, echo, or pass that raw value. The managed flow therefore does **not** enable/start the service and does **not** submit registration or approval transactions.

If an operator chooses to continue outside Valley, keep any operator-owned secret file permission-restricted (for example mode `0600`), outside source control and logs, and review the upstream exposure model first. This is a residual upstream limitation rather than a solved Valley secret path.

## Operations

Use the menu to:

- view logs and service status
- use the approval menu item to review the fail-safe boundary; execute any raw-key upstream approval manually only if you explicitly accept that limitation
- restart or stop the service
- delete the node only after backing up anything needed for recovery

For direct diagnostics, first identify the generated service name:

```bash
systemctl list-unit-files | grep -i alignment
sudo systemctl status <alignment-service>
sudo journalctl -u <alignment-service> -n 100 --no-pager
```

Do not paste private keys, signing material, or complete transaction payloads into issues or chat.

## Recovery

Before updates or deletion, record the installed release and preserve configuration. If the service fails, inspect the earliest startup error, verify RPC reachability and chain ID, then restore the last known-good configuration before reinstalling.

last updated by: John
