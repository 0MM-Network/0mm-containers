# ADR 0002: Shim contract and the manifest runtime field

## Status

Proposed. Mark promotes it to Accepted once the C1a pull request merges and its live lanes pass on the target host.

Supersedes 0mm-containers ADR 0001 §2 (privileged Ryuk row).

## Context

Bots run their toolchains in containers through thin shims from this package, never as host installs. Each shim used to carry its own `podman run` line. Every copy could drop a hardening flag, and nothing stopped a shim from asking for more than it needed. The contract has to hold now on rootless podman and later on other backends (the Nanos unikernel next, then krun or seL4 guests) without rewriting every shim.

ADR 0001 section 2 runs the Testcontainers Ryuk reaper with `TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED=true`. The dispatcher below refuses privileged containers, so the two decisions conflict for any suite that goes through it.

## Decision

### One dispatcher

`bin/0mm-run <manifest.toml> [args...]` is the only way a shim starts a container. Backends live in `bin/lib/0mm-run/<runtime>.sh`. The arguments after the manifest go to the tool inside the container, appended to the manifest's `command`.

### The manifest

One TOML file per tool. `shims/manifest.schema` is the single list of keys, their types, and their checks. The dispatcher reads it, so a key is added in one place. The file is a strict TOML subset: `key = value` lines, strings without escapes, booleans, integers, and one-line arrays of strings. Anything else is refused.

| Key | Type | Rule |
|-----|------|------|
| `runtime` | string, required | `podman` now, `nanos` next. `krun` and `sel4` are reserved and refused with `runtime <name> is reserved`. A runtime without a backend file is refused with `runtime <name> has no backend yet`. |
| `image` | string, required | Pinned by digest, `name@sha256:<64 hex>`. |
| `command` | array, required | Non-empty. |
| `network` | string | `none` (the default), `pasta`, or `slirp4netns`. `host` is refused. |
| `mounts` | array | `source:target:ro` or `source:target:rw`. The source is relative to `$AI_ROOT/cache/` and must resolve inside it. Shared caches mount `ro`. A `rw` mount must resolve under `$AI_ROOT/cache/<tool>/<bot>/`, where `<tool>` is the manifest file name without `.toml` and `<bot>` is `$OMM_BOT`, or the caller's user name when that is unset. Sockets, FIFOs and devices are refused; a source must be a file or a directory. Targets are absolute and outside `/work`. |
| `devices` | array | Only `/dev/kvm`, and only for `runtime = "nanos"`. |
| `env` | array | Variable names to forward from the caller. Names only, never values. |
| `pids_limit`, `memory`, `cpus` | int, string, string | Resource caps. Defaults `1024`, `4g`, `2`. |
| `privileged`, `cap_add`, `security_opt`, `userns`, `pid`, `ipc` | forbidden | Refused with `<key> is not allowed`. |

Any other key is refused as unknown.

### The podman backend

It always runs `podman run` with this floor, in this order, followed by the forwarded env names, the cache mounts, the work mount, the image, the command, and the arguments:

```
--rm --userns=keep-id --cap-drop=all --security-opt=no-new-privileges --read-only
--network=<network|none> --pids-limit=<n> --memory=<size> --cpus=<n>
--volume=$PWD:/work --workdir=/work
```

- The current directory is the only writable project mount, at `/work`. `--read-only` leaves podman's default writable tmpfs at `/tmp`.
- `--userns=keep-id` stays while `/work` is writable, so files the tool writes belong to the caller. A later slice moves manifests without a writable host mount to `--userns=auto` once it is shown to map the caller onto `/work`.
- The default seccomp profile applies. No flag can weaken it.
- No host environment passes by default.

### Fail closed

The dispatcher exits 2 with `0mm-run: refused: <reason>` before any `podman run` when any of these holds:

- The caller is root.
- `podman info` fails (`podman unavailable`) or reports a rootful engine (`podman is not rootless`).
- The manifest breaks a rule above, including `privileged = true`, which prints `0mm-run: refused: privileged is not allowed`.
- An argument equals one of `--privileged`, `--cap-add`, `--security-opt`, `--device`, `--volume`, `--mount`, `--network`, `--net`, `--userns`, `--pid`, `--ipc`, or is one of them followed by `=value`. Arguments belong to the tool, so these names are refused outright instead of being guessed at.
- The working directory is `/`, the caller's home, or contains `:` or `,`.

### Secrets

A secret value never appears in a manifest, an image, or an argument. A credential reaches a container only as a file mount read at call time, or through a variable name the manifest lists. This ADR adds no credential path.

### Ryuk

Ryuk stays disabled for every suite that runs through `0mm-run`: `TESTCONTAINERS_RYUK_DISABLED=true`, and the suite's `after()` stops its containers, backed by `--rm`. No privileged exception is granted. This supersedes the `TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED=true` row of ADR 0001 section 2 for those suites.

## Considered Options

- **Keep one `podman run` line per shim.** Rejected. Each copy can drift, and nothing refuses a weaker flag.
- **Parse the manifest with a TOML library on the host.** Rejected. It adds a host interpreter dependency and start-up cost to every call. The strict subset is enough for these keys and refuses what it cannot read.
- **Pass podman options through argv.** Rejected. It reopens every refusal the manifest closes.
- **Allow Ryuk privileged as an exception.** Rejected. It would be the only privileged container in the program, and suite teardown already cleans up.

## Consequences

- A new tool is a manifest file, not a new script.
- A new runtime is one backend file. Reserved names fail clearly until it exists.
- Tools that need a flag outside the floor need a schema change and a review, which is the point.
- Arguments named `--privileged`, `--cap-add`, `--security-opt`, `--device`, `--volume`, `--mount`, `--network`, `--net`, `--userns`, `--pid` or `--ipc` are refused even when they are the tool's own option. A `--` separator does not help, because every argument is checked. The workaround is the manifest: put the tool's option in the `command` array, which is not checked against these names, and ask for a container network, mount, or device through the `network`, `mounts`, or `devices` keys.
- Until host sudo is removed for the calling user, these refusals stop mistakes, not a determined caller.

## Evidence

- `test/unit/0mm_run_contract.bats`, run with `bin/bats test/unit/0mm_run_contract.bats`. It uses a fake `podman` that records its arguments, covers each refusal and the happy path, and asserts the exact `podman run` argument list for `test/fixtures/manifests/echo.toml`.
- Transcripts in `docs/evidence/c1a/`.
