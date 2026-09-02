# Valley of 0G Mainnet - Usage Guide

How to run the tool, how to navigate it, and what every menu option does.

## Running the tool

```bash
bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Mainnet/main/resources/valleyof0G.sh)
```

Or from a local clone:

```bash
bash resources/valleyof0G.sh
```

Run it as the user that owns the 0G node files. The script stores environment variables in `~/.bash_profile`.

## Navigation

- Choose an option by typing number + letter together, for example `1e`, or type the number first and then the letter when prompted.
- Validator, storage, KV, and AI alignment nodes are separate components. Pick the component you actually run.
- After exiting, run `source ~/.bash_profile` so exported variables apply to the current shell.

## Menu options explained

| Option | What it does | When to use | Destructive / risk |
|---|---|---|---|
| 1a. Deploy/re-Deploy Validator Node | Installs or reinstalls the 0G validator stack. | First setup or clean redeploy. | Yes - may replace services and data. Backup keys first. |
| 1b. Manage Validator Node | Opens validator node management/update flow. | Validator binary or service maintenance. | Medium. |
| 1c. Apply Validator Node Snapshot | Applies validator node snapshot. | Speed up sync or recover data. | Yes - can replace chain data. |
| 1d. Add Peers | Updates validator node peers. | Peer connectivity issues. | Low - config change. |
| 1e. Show Node Status | Shows local validator node status versus public height. | Quick height check. | No. |
| 1f. Show Validator Node Logs | Tails consensus and execution logs together. | Debug validator stack. | No. |
| 1g. Show Consensus Client Logs | Tails consensus logs. | Debug consensus issues. | No. |
| 1h. Show Execution Client Logs | Tails geth/reth logs. | Debug execution issues. | No. |
| 1i. Query Balance | Queries wallet balance. | Check funds before transactions. | No. |
| 1j. Create Validator | Registers a validator. | Initial validator setup. | Yes - on-chain transaction. |
| 1k. Delegate to Validator | Delegates 0G stake. | Increase stake or delegate to another validator. | Yes - on-chain transaction. |
| 1l. Undelegate from Validator | Starts undelegation. | Reduce or remove stake. | Yes - on-chain transaction. |
| 1m. Migrate Geth to Reth | Migrates execution client from geth to reth. | Experimental EL migration. | High - experimental service/data change. |
| 1n. Rollback & Align CL/EL Height | Recovery flow to align consensus/execution height. | Broken CL/EL sync recovery. | High - recovery operation. |
| 1o. Check & Withdraw Rewards | Opens staking rewards management for delegation value, operator commission, tip fees, and withdrawal queue. | Check validator earnings or submit reward-related validator-contract transactions. | Mixed - dashboard/delegation/queue checks are read-only; withdrawals and queue processing submit transactions. |
| 1p. Run Node Doctor | Runs read-only CL/EL health, sync, version, chain ID, Engine API, disk, clock, and RPC exposure checks. | Diagnose readiness before changing services or data. | No. |
| 2a. Deploy Storage Node | Stages the reviewed Storage binary, non-secret config, and service unit. It does not collect a miner key or start mining. | Prepare a fresh Storage installation before the operator-owned upstream secret step. | Medium - installs software; service remains disabled/stopped. |
| 2b. Update Storage Node | Updates storage node binary/service. | Storage node upgrade. | Medium. |
| 2c. Apply Storage Node Snapshot | Applies storage node snapshot. | Speed up or recover storage sync. | Yes - can replace storage data. |
| 2d. Change Storage Node | Changes the Storage blockchain RPC. Miner-key replacement is intentionally not automated. | Reconfigure a live Storage RPC endpoint. | Medium. |
| 2e. Show Storage Node Logs | Tails storage logs. | Debug storage node. | No. |
| 2f. Show Storage Node Status | Shows storage node status. | Health check. | No. |
| 3a. Deploy Storage KV | Installs Storage KV service. | Run KV component. | Medium. |
| 3b. Show Storage KV Logs | Tails Storage KV logs. | Debug KV component. | No. |
| 3c. Update Storage KV | Updates Storage KV. | KV upgrade. | Medium. |
| 4a. Run AI Alignment Node | Stages the verified Alignment binary, non-secret config, and optional disabled unit. | Prepare Alignment software without exposing the upstream raw service key. | Low - no service start or transaction. |
| 4b. Show AI Alignment Node Logs | Tails AI alignment logs. | Debug AI component. | No. |
| 4c. Approve AI Alignment Delegations | Explains the fail-safe boundary; Valley does not submit because upstream v1.0.0 requires a raw `--key` argument. | Review before any manual upstream approval. | No - Valley submits no transaction. |
| 5a. Restart Validator Node | Restarts validator stack. | After config or binary changes. | Low - downtime. |
| 5b. Restart Storage Node | Restarts storage service. | Storage maintenance. | Low. |
| 5c. Restart Storage KV | Restarts KV service. | KV maintenance. | Low. |
| 5d. Restart AI Alignment Node | Restarts AI service. | AI node maintenance. | Low. |
| 5e. Stop Validator Node | Stops validator stack. | Maintenance. | Medium - node offline. |
| 5f. Stop Storage Node | Stops storage service. | Maintenance. | Medium. |
| 5g. Stop Storage KV | Stops KV service. | Maintenance. | Medium. |
| 5h. Stop AI Alignment Node | Stops AI service. | Maintenance. | Medium. |
| 5i. Delete Validator Node | Deletes validator services/data. | Decommission or clean reinstall. | Yes - destructive. Backup keys first. |
| 5j. Delete Storage Node | Deletes storage service/data. | Decommission storage node. | Yes - destructive. |
| 5k. Delete Storage KV | Deletes KV service/data. | Decommission KV. | Yes - destructive. |
| 5l. Delete AI Alignment Node | Deletes AI alignment service/data. | Decommission AI node. | Yes - destructive. |
| 5m. Schedule Stop/Restart Validator Node | Schedules validator stop/restart. | Planned maintenance timing. | Medium - planned downtime. |
| 6. Install the 0gchain App | Installs CLI app only, without running a node. | Need transaction CLI only. | Medium - binary install. |
| 7. Show Grand Valley's Endpoints | Prints endpoints and links. | Reference. | No. |
| 8. Show Guidelines | Shows in-tool guidance. | First-time use. | No. |
| 9. Exit | Leaves the script. | Done. | No. |

## Recommended first-time flow

1. Run `1a`, then monitor with `1e`, `1f`, `1g`, and `1h`.
2. Create/register validator with `1j` only after the node is healthy and funded.
3. Use `1k` for delegation after confirming validator address and amount.
4. Add storage components (`2a`, `3a`, `4a`) only if you intend to operate those services.
5. Keep backups before any delete, migrate, snapshot, or rollback action.

## Staking rewards management

Use `1o` to open the 0G Mainnet staking rewards submenu. It can show a validator earnings dashboard, estimate a delegator's current delegation value, withdraw operator commission, withdraw operator tip fees, trigger `distributeRewards()`, inspect or process the withdrawal queue, and change the validator commission rate.

0G validator rewards are auto-compounding. Delegators do not claim rewards through a separate claim function; `distributeRewards()` folds pending rewards into the validator pool, which changes the token/share exchange rate. To withdraw only rewards, estimate the excess value above your principal and undelegate that amount.

Operator commission and tip fees are separate. `withdrawCommission(address)` is operator-only and enters the withdrawal queue, so it is not instant. `withdrawTipFee(address)` is also operator-only, but transfers instantly and does not use the queue.

`setCommissionRate(uint32)` is operator-only. The contract uses parts per million (ppm): `10000` is 1%, `50000` is 5%, and `1000000` is 100%. The submenu accepts a percentage with up to four decimal places, shows the current and proposed values, and asks for explicit confirmation before submission. The validator contract rejects values above the protocol maximum.

The withdrawal queue view shows the current block, sampled block time, each entry's completion height, remaining blocks, and an estimated wait time. `PENDING` means the current block is still below `completionHeight`; `READY` means the queue entry can be processed.

## Safety notes

- `1m` and `1n` are high-risk recovery/migration actions. Test on non-production where possible.
- In `1o`, never submit operator-only writes, including commission-rate changes, unless you are using the validator operator wallet.
- Any menu item that submits a transaction spends gas and may move funds or stake.
- Protect validator keys, EVM private keys, and service backups. Valley does not collect EVM wallet keys for validator/staking writes; Foundry prompts interactively.
- Storage v1.1.0 and Alignment v1.0.0 still require raw key material upstream. Valley does not move those secrets into argv, shell exports, app config, or generated units; the fresh install flows stop before the secret-dependent step.
