# pi-ai

Rootless Podman image + thin shim for [Pi](https://pi.dev) (`@earendil-works/pi-coding-agent`).

## Quick start

```bash
# Host requirements: podman, pasta (package: passt); Node ≥ 20 for contract tests
./install.sh               # builds localhost/pi:latest, installs shim
./pi --version
./test_shim.sh             # layer A: shim smoke / secret dry-run
./run-contract-tests.sh    # layer B: Testcontainers + Goss (in-guest)
```

Contract testing decisions (reuse for other packages): [`../docs/adr/0001-container-contract-testing.md`](../docs/adr/0001-container-contract-testing.md).

**XAI / provider key coverage**

| Check | Where |
|-------|--------|
| Guest has `XAI_API_KEY` when injected | `goss-provider-env.yaml` (layer B) |
| Image validates *without* a key | base `goss.yaml` + negative suite in `tests/contract.test.mjs` |
| Podman `--secret …,type=env,target=XAI_API_KEY` reaches guest | `test_shim.sh` secret→env e2e (layer A) |
| Shim wires `pi_XAI_API_KEY` | `test_shim.sh` dry-run + `pi --ensure-secrets` |

No test calls the xAI API or requires a real credential.

Optional: copy/link the shim into the AI toolchain path:

```bash
install -m 0755 ./pi ~/src/ai/bin/pi
```

`install.sh` does that automatically when `~/src/ai/bin` exists (or `AI_ROOT` is set).

## Runtime contract

| Host | Container |
|------|-----------|
| `$PWD` | `/work` (cwd) |
| `~/.pi` | `/home/node/.pi` (auth, settings, sessions) |
| `~/.grok` (when present) | `/home/node/.grok` (official grok CLI home; `bin/grok` on guest PATH) |
| `$AI_ROOT/cache/pi` | `/home/node/.cache/pi` |
| `$XDG_RUNTIME_DIR/podman/podman.sock` | `/run/podman/podman.sock` + `CONTAINER_HOST` (when socket is up) |
| `$AI_ROOT/cache/podman-remote/podman-remote-static-linux_amd64` | `/usr/local/bin/podman` and `podman-remote` (ro) |

Flags: `--userns=keep-id`, `--security-opt label=disable`, no privileged mode.

**In-container Podman** uses the host engine over the user API socket (not a nested rootless engine). Bootstrap enables:

```bash
loginctl enable-linger "$USER"
systemctl --user enable --now podman.socket
```

If the socket is missing, the shim still starts Pi and prints a one-line fix on stderr.

Provider keys prefer **Podman secrets** named `pi_<VAR>` (for example `pi_XAI_API_KEY`), injected as env vars via `--secret …,type=env,target=<VAR>`.

**Seeding secrets** (also for bootstraps that ran before secret support):

```bash
# Host (or in-guest via mounted podman.sock) — prompts for xAI if needed
./bin/pi --ensure-secrets

# Non-interactive
XAI_API_KEY=... ./bin/pi --ensure-secrets
```

On normal launch the shim also **auto-promotes** any provider key present in the host env into a missing `pi_<VAR>` secret (no overwrite). `bootstrap.sh` / `install.sh` call the same path. If a secret is still missing, the shim forwards the host env var with `-e` when set.

## Rebuild / pin version

```bash
PI_VERSION=0.82.1 ./install.sh
PI_IMAGE=localhost/pi:dev ./install.sh
```
