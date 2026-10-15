# Feature backlog: containerized OpenBao/Vault **test-server**

**Package law:** `0mm-containers/AGENTS.md`  
**Contract testing ADR:** `docs/adr/0001-container-contract-testing.md` (pi-ai reference)  
**Extend:** existing `0mm-containers/vault/` (OpenBao image/entrypoint) — do not invent a parallel image tree in `chef/`  
**Parent shims:** `$PROJECT_DIR/bin/*` via `_run` sidecar pattern (`bin/python`, `bin/bats`, …)  
**Blocks:** chef inflight **S6** and any live bao E2E that could touch host `127.0.0.100:8200` / host raft

## Problem

Host Vault0 holds **real data**. Live tests that share VIP `127.0.0.100:8200` or `VAULT_ZERO_HOME` under the chef checkout are **not hermetic**. S6 and factory-live paths must not run against that instance.

## Fitness note (2026-08-11)

As-built `0mm-containers/vault/test_shim.sh` and related autounseal demos are **not** this test-server — they couple to host VIP and are **anti-fit**. Monorepo **G0** must go green before Transit0 product work: `docs/features/vault0-transit0/fitness/`, `docs/design/2026-08-11-e2e-trial-vehicle-fitness.md`.

## Goal

A **fully containerized** OpenBao test-server, managed under `0mm-containers`, reached only through **thin monorepo shims**, with **fail-closed isolation** from the host desktop Vault0.

## Feature index

| File | Topic |
|------|--------|
| `10_isolation_guarantees.feature` | Hard isolation from host VIP, ports, raft, tokens |
| `20_package_layout_and_image.feature` | Extend `vault/` package; image build; OpenBao pin |
| `30_sidecar_shims.feature` | `$PROJECT_DIR/bin` shims + `_run`; nested Pi / `PROJECT_DIR_HOST` |
| `40_lifecycle_and_api.feature` | Start/stop/ready/init/unseal/seed API for tests |
| `50_contract_tests_goss_testcontainers.feature` | Layer A shim + Layer B Goss/Testcontainers |
| `60_chef_consumer_integration.feature` | How chef bats/pytest **must** consume the test-server |
| `70_security_and_non_goals.feature` | Secrets, no host keyring, non-goals |
| `80_transit_consumer_trial_profile.feature` | **Transit0 trial:** test-server as seal **consumer** (not parent); gate before host Vault0 migrate |

**Cross-cut migration SSOT:** `$PROJECT_DIR/docs/features/vault0-transit0/migration/70_trial_migrate_e2e_test_server.feature`

## Tags

| Tag | Meaning |
|-----|---------|
| `@backlog` | Not implemented / not CI-green yet |
| `@pending` | Scenario awaiting automation |
| `@core` | Must pass before any chef live-vault test is re-enabled |
| `@isolation` | Host-data safety |
| `@shim` | bin/ sidecar entrypoints |
| `@0mm` | Lives under 0mm-containers |

## Implementation order (when coding starts)

1. Features here stay SSOT — **no** host prove scripts as DoD.  
2. Extend `vault/` image + goss + testcontainers (copy pi-ai pattern).  
3. Install shims into `$PROJECT_DIR/bin/` (e.g. `bao-test`, `vault0-test-server`).  
4. Chef: gate live E2E on shim; refuse host VIP/ZERO_HOME.  
5. Only then un-block S6 / factory-live against **container** endpoints.  
6. **G0 fitness first** (monorepo fitness/*): isolation shim, raft-shamir, factory-on-vehicle, anti-patterns cleared — **blocks Transit0 impl**.  
7. **Transit trial (after G0 + Transit0 Phase 1):** `--profile=transit-consumer` (feature 80) + migration/70 **before** host Vault0 seal migrate.

## Run automation (future)

```bash
# From workspace root — heavy tools via shims only
bin/bats 0mm-containers/vault/test_shim.sh          # or package bats
bin/python -m pytest …                              # if Node not used
# Contract (pi-ai pattern):
cd 0mm-containers/vault && ./run-contract-tests.sh
```
