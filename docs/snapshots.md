# Snapshot Guide

Snapshots replace node database state to reduce sync time. Treat every snapshot operation as destructive maintenance.

## Before You Start

1. Confirm the snapshot matches mainnet and the selected component.
2. Check the published height, age, source, and checksum when available.
3. Ensure free space for the compressed archive, extracted data, and rollback copy.
4. Record the current service status, binary version, config, and local height.
5. Back up keys and configuration separately from node data.
6. Test the procedure on a non-validator or staging node first.

Never replace validator keys, node keys, JWT files, or configuration with files from a public snapshot.

## Launch

```bash
bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Mainnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
```

- **Validator:** select **Validator Node** → **Apply Snapshot**.
- **Storage:** select **Storage Node** → **Apply Snapshot**, then choose Standard or Turbo to match the node configuration.

## Verification

After extraction:

1. Confirm ownership and permissions match the service user.
2. Start only the services required for that node.
3. Inspect the first 100 log lines after startup.
4. Verify local height advances toward the network tip.
5. Keep the rollback copy until the node is stable.

```bash
sudo systemctl status 0gchaind
sudo journalctl -u 0gchaind -n 100 --no-pager
curl -s http://127.0.0.1:26657/status | jq '.result.sync_info'
```

For Storage nodes, replace the service checks with `zgs` and verify its JSON-RPC status.

## Failure Recovery

If download, extraction, or startup fails:

1. Stop the affected service.
2. Preserve the failed logs and snapshot metadata.
3. Move the failed database aside; do not overwrite the rollback copy.
4. Restore the previous database and configuration.
5. Start the service and verify its original health before retrying.

Do not repeatedly apply snapshots until the actual failure—space, checksum, archive, permissions, version, or configuration—is identified.

## Related Documentation

- [Validator Node Guide](validator-node.md)
- [Storage Node Guide](storage-node.md)

last updated by: John
