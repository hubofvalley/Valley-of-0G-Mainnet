# Node Doctor

`resources/0g_node_doctor.sh` is a read-only diagnostic for the 0G validator
stack. It treats `0gchaind` as the consensus layer (CL) and the active Geth or
Reth service as the execution layer (EL).

## Run it

From the repository:

```bash
bash resources/0g_node_doctor.sh
bash resources/0g_node_doctor.sh --json
```

The menu exposes the same check at **Validator Node → p. Run Node Doctor**.
The JSON output has a stable `schema_version`, `overall`, `ready`, component
state, joint CL/EL state, and per-check `status`/`detail` values.

## What it checks

- actual active services from `systemctl`; it does not trust `EXEC_CLIENT`;
- CL CometBFT status, `catching_up`, height, and peers;
- EL JSON-RPC, `eth_syncing`, height, chain ID, and peers;
- CL/EL head convergence and Engine API TCP listener (socket presence only);
- deployed binary versions against `VERSIONS.json` where binaries are visible;
- disk headroom, NTP synchronisation, and public RPC listener exposure;
- accidental simultaneous Geth and Reth service activation.

Readiness is joint: both layers must be available, the CL and EL must report
healthy sync state, their heads must be within the configured lag limit, the
chain ID must match, the CL head timestamp must be fresh, and the Engine API
listener must be present. The CL must be running while the EL catches up; the
doctor never treats EL sync as a prerequisite for starting the CL. A listening
Engine port is not proof of JWT-authenticated Engine API traffic.

The shipped port defaults are CL RPC `26657`, EL HTTP RPC `26545`, and Engine
API `26551`. The doctor reads the CL RPC port from `config.toml` when available,
then derives the EL/Engine ports from the same prefix. Use explicit
`DOCTOR_*_PORT` overrides for custom layouts.

The expected CometBFT network defaults from `VERSIONS.json` to
`0G-mainnet-aristotle`. `DOCTOR_EXPECTED_CL_NETWORK` may override it for a
controlled fixture or alternate deployment; it remains a critical check.

## Exit status and safety

- `0`: all critical checks pass and the stack is ready;
- `1`: a critical check is unhealthy or unavailable; inspect the JSON checks
  before taking action. Advisory warnings/failures are reported but do not
  block readiness;
- `2`: invalid usage, missing dependency, or invalid manifest.

The doctor never starts, stops, restarts, enables, disables, or modifies a
service. It does not read private-key or JWT contents. A warning is not an
authorisation to restart a production validator; review the evidence first.

last updated by: John
