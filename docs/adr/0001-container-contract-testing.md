# ADR 0001: Container contract testing (Testcontainers + Goss)

## Status

Accepted — **pi-ai is the reference implementation**.  
All other `0mm-containers` packages should follow this ADR unless a later ADR supersedes it.

## Context

`0mm-containers` packages share a shape: rootless Podman image + thin host shim (often installed under `~/src/ai/bin`). Historical checks are bash smoke scripts and BATS. `AGENTS.md` requires:

- **Testcontainers** (language-native library) orchestrates lifecycle, mounts, readiness, cleanup.
- **Goss** validates *inside the guest only*.
- No Goss-on-host; no Testcontainers-as-dgoss/DinD wrapper.
- Config/contract tests stay separate from application or observability tests.

This ADR records decisions proven on pi-ai so gsd-ai, goose-ai, vault, terraform, … can copy without re-litigating.

## Decisions

### 1. Two layers (always keep both)

| Layer | Tooling | Owns |
|-------|---------|------|
| **A. Shim / engine smoke** | `<pkg>/test_shim.sh`, optional `bin/verify-shims` | Shim syntax, `--dry-run`, image presence, **Podman secret → `--secret …,type=env,target=…`**, throwaway secret→env e2e, host socket/pasta/subuid as needed |
| **B. In-guest contract** | Node Testcontainers + Goss | One (or few) long-lived containers per suite; mounts, binaries, `HOME`/cwd, env the **orchestrator** injected |

**Out of scope for A and B:** provider HTTP, OAuth, TUI, model quality, nested app workflows.

### 2. Orchestrator: Node Testcontainers → rootless Podman API

| Choice | Value |
|--------|--------|
| Library | `testcontainers` (Node), lockfile in `test/contract/package-lock.json` |
| Node | ≥ 20 on PATH (host preferred; in-guest Node works if path/socket rules below are followed) |
| Engine | User Podman socket — not Docker, not DinD |
| Shared code | `0mm-containers/test/contract/lib/{env,goss-bin,harness}.mjs` only — **do not fork per package** |

**Env (via `lib/env.mjs`):**

| Variable | Host run | Nested run (inside a package container talking to host socket) |
|----------|----------|------------------------------------------------------------------|
| Client socket | `$XDG_RUNTIME_DIR/podman/podman.sock` | Often `/run/podman/podman.sock` (shim mount) |
| `DOCKER_HOST` | `unix://<client socket>` | same |
| `TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE` | **host** socket path (for Ryuk binds) | **host** path `$XDG_RUNTIME_DIR/podman/podman.sock`, *not* the guest mount path |
| `TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED` | `true` | `true` if Ryuk enabled |
| `TESTCONTAINERS_RYUK_DISABLED` | unset/false when Ryuk works | **`true`** — Ryuk publish is not reachable from inside the agent container; suite `after()` must `stop()` |

**Container create defaults (`lib/harness.mjs` → `RootlessPodmanContainer`):**

- `UsernsMode=keep-id` (subclass sets `hostConfig`; testcontainers@11 has no `withUsernsMode`)
- `withSecurityOpt("label=disable")`
- Entrypoint overridden to `bash -c 'sleep infinity'` so Goss can `exec` repeatedly
- Production `ENTRYPOINT` is asserted **in Goss** (`command:`), not by starting the suite with it
- Bind-mount suite workdir → package work mount (pi: `/work`)
- `WorkingDir` = that mount
- `HOME` / default user are **package-specific** (pi: `HOME=/home/node`)

**Bind-mount paths must be engine-host paths.**  
When tests run on the host, `path.resolve` is enough. When tests run *inside* a container, client paths like `/work/…` are invalid on the engine — `harness.resolveEnginePath()` maps via `podman inspect <self> .Mounts`. Packages must not bypass this helper for binds.

**Suite workdirs** must live on a host-visible tree when nested (e.g. `$PROJECT_DIR/cache/…` or `/work/cache/…`). Do **not** use container-local `os.tmpdir()` for mount-marker tests under nested runs.

### 3. Validator: Goss from shared cache (never in app images)

- Binary: `$PROJECT_DIR/cache/goss/goss` (pin in `lib/goss-bin.mjs`, currently **v0.4.9**).
- Mount/copy into guest at `/opt/contract/goss` + YAML under `/opt/contract/`.
- Invoke only via Testcontainers `exec`:  
  `goss -g /opt/contract/<file>.yaml validate --format documentation`
- **Never** `apt install goss` on the host as a permanent package.
- **Never** bake Goss into production Containerfiles.

**Goss 0.4.x pitfalls (reuse these fixes):**

- Prefer `file.contents` (not deprecated `file.contains`).
- `filetype: file` fails on symlinks (e.g. npm global bins) — assert `exists` or `filetype: symlink`.
- Prefer `command.exec` shell checks for version strings over fragile `stdout:` pattern lists.
- Use native `environment:` for injected env contracts.

### 4. Repository layout (copy this)

```
0mm-containers/
  docs/adr/0001-container-contract-testing.md    # this file
  test/contract/                                 # SHARED — one copy
    package.json
    package-lock.json
    README.md
    lib/env.mjs
    lib/goss-bin.mjs
    lib/harness.mjs
  <package>/                                     # e.g. pi-ai, gsd-ai
    Containerfile
    install.sh
    <shim>                                       # thin launcher
    goss.yaml                                    # base contract (no secrets required)
    goss-provider-env.yaml                       # optional provider env package
    tests/contract.test.mjs                      # thin suite; imports shared harness
    run-contract-tests.sh                        # sets PROJECT_DIR, socket, npm cache; node --test
    test_shim.sh                                 # layer A
```

**gitignore:** this repo uses a whitelist (ignore `*`, then un-ignore). When adding a package’s contract files, ensure patterns allow `goss*.yaml`, `tests/**`, `run-contract-tests.sh`, and `test/contract/**` (already done for the shared harness).

### 5. Secrets and provider env

| Concern | Layer | Rule |
|---------|-------|------|
| Create/refresh Podman secrets | A (shim) | `<pkg> --ensure-secrets` and/or auto-promote env → secret when missing |
| Secret naming | A | `<packageShort>_<ENV_NAME>` — `pi_XAI_API_KEY`, `gsd_XAI_API_KEY`, … |
| Inject at run | A | `--secret name,type=env,target=ENV_NAME` preferred; else `-e` from host env |
| Assert CLI wiring | A | `--dry-run` matches `--secret` / `type=env` / `target=` |
| Assert secret→guest env | A | Throwaway secret name (e.g. `pi_contract_e2e_XAI_API_KEY`) + `podman run --secret …`; **never** overwrite the user’s real secret in tests |
| Assert guest env surface | B | Testcontainers `.withEnvironment` + `goss-provider-env.yaml` |
| Negative: no key | B | Base `goss.yaml` **passes**; provider goss **fails** |
| Real credentials / provider API | neither | Out of scope |

**Do not** require provider keys in base `goss.yaml`.  
**Do not** expect Testcontainers/Docker API to exercise Podman secrets — that stays layer A.

### 6. What Goss may and may not assert

**May:** guest paths, mount visibility of host-seeded files, commands/binaries the image claims, guest env, simple file content under mounted workdirs.

**May not:** host filesystem outside mounts, host `podman secret ls`, registry auth, provider connectivity, TUI, performance.

### 7. Lifecycle and isolation

- Prefer **one container per describe/suite** (`before` / `after`), not per `it`.
- Always `stop()` in `after` even when Ryuk is on (defense in depth).
- No privileged **app** containers; Ryuk may be privileged under rootless Podman.
- No nested Docker-in-Docker.
- Clean marker dirs under `$PROJECT_DIR/cache/` in `after`.

### 8. Caches and pins

| Artifact | Location | Pin |
|----------|----------|-----|
| npm (testcontainers) | `$PROJECT_DIR/cache/npm` (`npm_config_cache`) | `test/contract/package-lock.json` |
| Goss binary | `$PROJECT_DIR/cache/goss/goss` | `GOSS_VERSION` in `goss-bin.mjs` |
| Package runtime caches | `$PROJECT_DIR/cache/<pkg>/…` | package-defined |

`$PROJECT_DIR` defaults to `$HOME/src/ai` on the host; when the suite runs with workdir `/work`, export `PROJECT_DIR=/work` (or the host path). Bump pins in this ADR’s decision log.

### 9. Package porting checklist

For each new package (gsd-ai, goose-ai, vault, …):

1. **Image contract** — list mounts, `HOME`, user, binaries, workdir (may differ from pi’s `/work` + `/home/node`; encode in `goss.yaml` and harness options).
2. **Add** `<pkg>/goss.yaml` (base only).
3. **If** the shim injects provider keys: add `goss-provider-env.yaml` + positive/negative suites (copy pi-ai `tests/contract.test.mjs` structure).
4. **Add** `tests/contract.test.mjs` importing `../../test/contract/lib/harness.mjs` (adjust relative path if package depth differs).
5. **Add** `run-contract-tests.sh` (copy pi-ai; change image env var / paths only).
6. **Extend** `test_shim.sh`: syntax, dry-run, secret dry-run, **throwaway** secret→env e2e, mount check with `--entrypoint` override if `ENTRYPOINT` is an app binary.
7. **Shim secrets:** `--ensure-secrets` + `pkg_<ENV>` naming; document in package README.
8. **Do not** duplicate `test/contract/lib` — fix the shared harness if something is missing.
9. **Run on host first** (`./run-contract-tests.sh`); nested runs are supported but stricter (path map + Ryuk off).
10. **Whitelist gitignore** if new paths are ignored by `*`.

### 10. Hyperlight / Unikraft (forward-looking)

No guest networking assumed: host seeds input; guest→host calls for fetch. Prefer Podman or Firecracker/urunc when real sockets are required. If the runtime is not Docker-API compatible, orchestration may leave Testcontainers — **new ADR**, keep Goss-as-in-guest-validator if possible.

## Reference (pi-ai)

```bash
# Layer A
./0mm-containers/pi-ai/test_shim.sh
./bin/verify-shims

# Layer B (host preferred)
PROJECT_DIR=$HOME/src/ai ./0mm-containers/pi-ai/run-contract-tests.sh

# Nested (inside pi): export PROJECT_DIR=/work; Ryuk auto-disabled; paths resolved via inspect
```

Shared harness entry: `startContractContainer({ image, workDir, gossFiles, env?, home?, user? })`.

## Consequences

**Positive**

- One harness, many packages; credentials not required for CI-like contract runs.
- Production images stay free of test tooling.
- Clear split: shim owns Podman secrets; Goss owns guest truth.

**Negative / costs**

- Node + npm cache required for layer B.
- Nested Testcontainers needs path translation and usually Ryuk disabled.
- Whitelist gitignore must be updated when adding paths.

**Follow-ups**

- Port gsd-ai, goose-ai, vault, … using §9 checklist.
- Optional later: `~/src/ai/bin/contract-test` launcher if host Node is removed.
- Optional later: language-agnostic harness if Node is undesirable — new ADR.

## Decision log

| Date | Note |
|------|------|
| 2025-07-30 | Accepted; pi-ai reference |
| 2025-07-30 | Nested runs: host socket override, Ryuk disable, `resolveEnginePath`, workdir under `$PROJECT_DIR/cache` |
| 2025-07-30 | Provider env: base goss key-free; provider goss ± suites; layer A throwaway secret e2e |
| 2025-07-30 | Expanded §9 porting checklist for remaining `0mm-containers` packages |
