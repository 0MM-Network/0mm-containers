# Rootless MergerFS for Opencode Skills Union

[![Bash](https://img.shields.io/badge/Bash-5.1%2B-blue?logo=bash)](https://www.gnu.org/software/bash/)
[![MergerFS](https://img.shields.io/badge/MergerFS-2.32.0-orange?logo=linux)](https://github.com/trapexit/mergerfs)
[![FUSE](https://img.shields.io/badge/FUSE-3-green?logo=linux)](https://github.com/libfuse/libfuse)
[![Bats](https://img.shields.io/badge/Tests-Bats-brightgreen?logo=bats-core)](https://github.com/bats-core/bats-core)

Rootless FUSE `mergerfs` scripts union directories listed in [`skills.txt`](skills.txt) into `./skills`:
- **Flat**: Merged files directly in `./skills/`
- **Prefixed**: `./skills/&lt;skillname&gt;/` subdirectories

Live read/write, `mfs` policy (most free space), idempotent, Podman-rootless compatible.

## Quick Start

1. **Deps** (Debian/Ubuntu):
   ```bash
   sudo apt update &amp;&amp; sudo apt install -y mergerfs fuse3 util-linux bats
   sudo usermod -aG fuse $USER  # relogin!
   ```

2. **skills.txt** (dirs to union, rel/absolute):
   ```
   ../../terraform/bats/
   ./skill1/
   ./skill2/
   ```

3. **Mount**:
   ```bash
   chmod +x skills-*.sh
   ./skills-mount.sh -v  # Flat union (idempotent)
   ls ./skills/          # Unified view
   ```

4. **Unmount**:
   ```bash
   ./skills-unmount.sh -f  # Force if busy
   ```

## Usage

All scripts: `set -Eeuo pipefail`, `getopts`, logging (stderr + journald), FUSE locks.

### Flat Union (`./skills-mount.sh` / `./skills-mount-flat.sh`)
```
./skills-mount.sh [-d] [-v] [-p &lt;policy&gt;] [-h]
  -d Dry-run
  -v Verbose
  -p Policy (default: mfs)
  -h Help
```
- Idempotent (`mountpoint` check)
- Auto-installs `mergerfs`
- Traps: lazy `fusermount -u -z`
- Lock: `/tmp/skills-mount*.lock`

### Prefixed (`artifacts/prefixed/skills-mount-prefixed.sh`)
```
Similar flags; mounts each dir to `./skills/&lt;basename&gt;/`
```

### Unmount (`./skills-unmount.sh`)
```
./skills-unmount.sh [-f] [-v] [-h]
  -f Force-kill busy procs (`fuser -km`)
```

## Rootless Podman

Mount host skills:
```bash
podman run -it --userns=keep-id -v $(pwd)/artifacts:/work -v /host/skills:/host/skills ...
cd /work &amp;&amp; ./skills-mount.sh
```

## Tests

```bash
bats test_mount.bats test_unmount.bats
```
- Idempotency, dry-run, policy, help, busy-checks.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Transport endpoint not connected` | `./skills-unmount.sh -f` |
| `Permission denied` | `groups | grep fuse`; relogin |
| `Mount in progress` | `rm /tmp/skills-*.lock`; retry |
| `fusermount: mount failed` | `id -Gn \| grep fuse`; deps |
| Not in `mount` | `mountpoint ./skills` (FUSE) |
| Busy unmount | `fuser ./skills`; `-f` |

**Policies**: [mfs](https://trapexit.github.io/mergerfs/#mfs), [ffr](https://trapexit.github.io/mergerfs/#ffr), etc.

See [prompt](prompt-skills-mergefs.md) for generation.

