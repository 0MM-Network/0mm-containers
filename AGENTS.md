# AGENTS.md — 0mm-containers

Rules for work **inside this tree** (`0mm-containers/`).  
Parent monorepo (`$AI_ROOT`) hosts this directory as a **git subrepo** — see parent `docs/adr/0002-git-subrepo-tdd-bdd.md`.

## Role

Reusable rootless container images, install scripts, shims, and **contract tests** (Testcontainers + Goss). Prefer existing artifacts here over inventing new host packages or one-off Containerfiles in the parent repo.

**Host bootstrap entry (this package):** `bootstrap.sh` — resolves workspace root, optionally seeds a missing parent `AGENTS.md`, optional Pi image/shim when present. Run as `./0mm-containers/bootstrap.sh` from a parent workspace (or set workspace env).

**Genericity (mandatory):** `bootstrap.sh` and any **seeded** parent `AGENTS.md` must stay **product-agnostic** — no parent monorepo mission, hardware envelope, Salt/ShellSpec installers, or provider secrets.  
- Review: `docs/reviews/2026-08-08-bootstrap-sh-genericity.md`  
- Decision backlog (features): `docs/features/bootstrap-genericity/`  
- Tests: `test/unit/bootstrap_genericity.bats` — **must** run via **`bin/bats`** (see `docs/features/bootstrap-genericity/80_bin_bats_runner.feature`); not bare `bats` on PATH as the contract  
- **Private HTTPS git-subrepo (generic):** implementation `bin/lib/bootstrap_private_subrepo`; thin `bin/bootstrap_private_subrepo` shim; optional Salt formula `bin/lib/salt/bootstrap_private_subrepo.sls`. Env `REPO_URL`, `DEST_DIR`, `GH_USER`, `GH_TOKEN` (or prompt on TTY). No hard-coded org/repo. Install via `bootstrap.d/0060-*.sh` → `$BTSTRP_ROOT/bin/lib/` (+ `bin/lib/salt/`). Bootstrap only **prints** next step (no auto-clone, no monorepo Salt apply). Gherkin: `docs/features/bootstrap-private-subrepo/`. Requires parent git + `git subrepo` (from install-dev-tools).



## Obtain / update (subrepo — not a nested clone)

- **Never** leave a long-lived nested `git clone` with its own `.git` under `0mm-containers/` in normal workflow.
- Metadata: `0mm-containers/.gitrepo` (managed by git-subrepo).
- From parent `$AI_ROOT` (git-subrepo on `PATH` via `bin/dev-tools-env`):
  - `git subrepo pull 0mm-containers`
  - `git subrepo push 0mm-containers` (when publishing upstream)
- Upstream reference: `https://github.com/0MM-Network/0mm-containers.git` (or configured remote in `.gitrepo`).

## Runtime conventions (shims and images)

These are **package** rules for building/running containers and writing shims — not monorepo-root product policy.

- Rootless Podman only (no Docker daemon, no privileged containers).
- Prefer **`--userns=keep-id`** so host UID/GID match the work tree.
- Mount the current working directory as **`/work`** (or the path established by the specific package).
- Mount shared host caches from `$AI_ROOT/cache/...` into relevant builds/runs.
- Thin bash shims under parent `$AI_ROOT/bin/` may wrap images produced here; permanent tools stay in containers.
- Day-to-day Pi entrypoint, once shipped: containerised `$AI_ROOT/bin/pi` shim — not a host-global Pi install.

## Contract testing (mandatory for image/package changes)

- **Testcontainers** = orchestration library (language-native, not a CLI): start containers, bind mounts, readiness, cleanup (Ryuk).
- **Goss** = in-guest validator: mounts (e.g. `/work`), required binaries, environment, critical paths via `goss.yaml` executed **inside** the container through Testcontainers exec.
- Do **not** use Goss to inspect the host.
- Do **not** use Testcontainers merely to drive dgoss via Docker-in-Docker.
- Prefer one container lifecycle per test suite/class; reset observable state between tests; never leave orphaned containers.
- Keep configuration tests (Goss) separate from application-level or observability tests.
- Reference: `docs/adr/0001-container-contract-testing.md`  
  Harness: `test/contract/` (e.g. pi-ai first package).

### Hyperlight / unikraft targets

- Assume no native guest networking unless the target explicitly provides it.
- Model data movement as host-seeded input, guest-to-host calls for external fetch, host delivery of results.
- Prefer Firecracker/urunc or ordinary Podman when the workload needs real sockets or inbound listeners.

## Test-first in this package

- Add/adjust contract tests (and any package-local unit tests) **before** implementation commits.
- Red → green → refactor; no large multi-file spikes without a failing test first.

## Layout cues

| Path | Role |
|------|------|
| `docs/reviews/2026-08-18-python-shim-pytest-rca.md` | bin/python pytest RCA (backlog features/) |
| `docs/adr/0001-container-contract-testing.md` | Contract-test decisions |
| `test/contract/` | Shared harness |
| `pi-ai/` | Example package (image, goss, shim tests) |
| `packer/` | Optional Packer image for OCI smoke (ckrd-vps Floci) |
| Other package dirs | Same pattern: image + goss + tests |

## Style

- Small, reviewable changes.
- Declarative Containerfiles; thin shims over complex bash.
- Check existing packages before adding new ones.
