# Contract test harness (Testcontainers + Goss)

Shared **layer B** for all `0mm-containers` packages.

**Authoritative decisions + porting checklist:**  
[`docs/adr/0001-container-contract-testing.md`](../../docs/adr/0001-container-contract-testing.md)

## Layout

| Path | Role |
|------|------|
| `lib/env.mjs` | Rootless Podman socket → Testcontainers env (host vs nested) |
| `lib/goss-bin.mjs` | Pin/download Goss → `$AI_ROOT/cache/goss/goss` |
| `lib/harness.mjs` | `startContractContainer`, `resolveEnginePath`, `runGoss` |
| `package.json` / lockfile | `testcontainers` only |

Package-specific: `<pkg>/goss.yaml`, optional `goss-provider-env.yaml`, `tests/contract.test.mjs`, `run-contract-tests.sh`, `test_shim.sh`.

## Prerequisites

- Rootless Podman + `systemctl --user enable --now podman.socket`
- Node ≥ 20
- Package image built

## Install deps once

```bash
export AI_ROOT="${AI_ROOT:-$HOME/src/ai}"
export npm_config_cache="${AI_ROOT}/cache/npm"
cd "$(dirname "$0")"
npm install
```

## Run

Prefer the package wrapper (host):

```bash
../pi-ai/run-contract-tests.sh
```

## Porting another package

Follow **§9 Package porting checklist** in the ADR. In short: reuse this directory; add package `goss*.yaml` + thin `tests/contract.test.mjs`; do not fork `lib/`.
