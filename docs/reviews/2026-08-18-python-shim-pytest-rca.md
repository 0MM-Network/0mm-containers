# RCA — control-plane `bin/python` cannot run pytest (2026-08-18)

**Status:** backlog — do not lose  
**Trigger:** host-nomad S1 (`chef/salt0/tests/test_nomad_s1.py`) could not run via the Pi/agent PATH.  
**Quote:** “The container python shim is broken for pytest.”  
**Law:** ADR 0006 (Pi thin; CPython in sidecar). Package work under `0mm-containers/` (images + shims + contract tests).  
**Features:** `docs/features/python-shim-pytest/`  
**Parent pointer:** `spec/backlog.paths` (same pattern as vault0-test-server).

## What failed (observed)

| Attempt | Result |
|---------|--------|
| `python -m pytest chef/salt0/tests/test_nomad_s1.py` | `/usr/local/bin/python: No module named pytest` |
| `chef/salt0/.pytest-pkgs/bin/pytest` shebang `#!/usr/local/bin/python` | `cannot execute: required file not found` |
| `/usr/local/bin/python` on the Pi guest | **ENOENT** |
| PATH `python` / `python3` | `/work/bin/python` → `bin/_run` + **`docker.io/library/python:3.12-slim-bookworm`** |

Workaround used: parent **ShellSpec** for S1 file asserts. Chef L1 pytest remains unrun in this environment.

## Root causes

| ID | Cause | Evidence |
|----|--------|----------|
| **RC1** | Parent `bin/python` does **not** use `localhost/ai-python-cp:local` or `0mm-containers/python`. It hardcodes stock **slim** CPython (no pytest). Comment on `bin/python` says “Prefer localhost/ai-python-cp:local” and then ignores it. | `bin/python` → `_run` `docker.io/library/python:3.12-slim-bookworm` |
| **RC2** | Sidecar `python -m pytest` uses the **image** site-packages. Chef’s vendored `chef/salt0/.pytest-pkgs` is on the mounted tree but is **not** on the container `PYTHONPATH` unless `_run` forwards it. Slim image has no pytest. | `-m pytest` → no module |
| **RC3** | No `bin/pytest` control-plane shim. `0mm-containers/python/install.sh` *can* emit a pytest wrapper for `localhost/python-runner`, but that is **not** what parent `bin/` installs. | no `bin/pytest`; two unused/divergent images |
| **RC4** | Chef pytest launcher shebang is **`#!/usr/local/bin/python`**. Pi guest has no that path (CPython is not apt-installed in pi-ai — ADR 0006). Shebang **bypasses** `PATH` / `bin/python`. | ENOENT on shebang |
| **RC5** | **Three** Python stories: (a) stock slim via `bin/python`, (b) `images/python-cp` (`localhost/ai-python-cp:local`, stdlib+pip, no pytest pin), (c) `0mm-containers/python` (venv + pytest). No single contract. | three Containerfiles / tags |

**Not the root cause:** Chef tests being “wrong.” They are valid L1 in chef. The control-plane interpreter contract failed them.

**Related (same family, not this ticket’s only fix):** `bin/shellspec` is a **broken symlink** to `/home/hedge/src/ai/cache/shellspec` (host path). Nested Pi used `cache/shellspec/bin/shellspec` instead. Track as a **sibling** scenario if not already covered by `spec/workflow/cp_shims_host_path_spec.sh`.

## Remedy (implementation later — oasis / 0mm-containers)

1. One SSOT image for `bin/python` / `bin/python3` (prefer `localhost/ai-python-cp:local` built from package or parent `images/python-cp`).  
2. That image (or a documented extra) must run `python -m pytest` against `/work` with forwarded `PYTHONPATH`.  
3. Ship `bin/pytest` via `_run` (same image).  
4. Contract tests in `0mm-containers/` (Goss + Testcontainers) + parent ShellSpec: pytest smoke on a tiny fixture; shebang or documented `python -m pytest` path.  
5. Do **not** `apt install python3` in pi-ai.  
6. Chef may keep L1 pytest; document `bin/python -m pytest` + PYTHONPATH, not `/usr/local/bin/python`.

## Non-goals

- Putting CUDA/torch in the CP Python image.  
- Replacing chef pytest with ShellSpec as chef’s L1 SSOT.  
- Host-global Python.
