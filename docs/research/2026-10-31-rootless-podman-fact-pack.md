# Stub: rootless Podman, shim contract, and hardened path (NanoVMs Nanos/ops, seL4)

The full research note is private. This stub only says where it lives and what it covers.

- **Canonical note:** private repo `0mm-mark/ai`, branch `bot/researchy/research-packs-rebuild`, path `docs/research/2026-10-31-rootless-podman-fact-pack.md`.
- **Why private:** it records deployment-specific security details that don't belong in a public repo.
- **Provenance:** compiled 2026-10-31; restored 2026-11-18 after a workspace rollback.

## Generic summary

- **Requirements.** Every tool runs in a container through `0mm-containers` shims. Rootless Podman is the minimum standard, and swapping a tool's runtime must be a data change, not a shim rewrite.
- **Shim pattern.** The recommendation is one dispatcher (busybox-style `argv[0]` symlinks) that reads a per-tool manifest with a `runtime` field, so TTY, UID mapping, signals and secrets are handled in one code path. This matches ADR 0002 in this repo.
- **Rootless baseline.** Read-only root, drop all capabilities, `no-new-privileges`, the default seccomp profile, user-namespace mapping, and resource limits. Config files alone are not enforcement; the dispatcher has to refuse rootful or privileged runs.
- **Hardened path.** NanoVMs Nanos/ops is the confirmed unikernel backend, run through the same shim contract. A Linux guest on an seL4 VMM is a later, separate spike.
- **MVP.** A Rust hello world built in a rootless toolchain container, then run as a Nanos unikernel through the same shim.

Claims in the full note are as checked on 2026-10-31 and are marked UNVERIFIED where unchecked.
