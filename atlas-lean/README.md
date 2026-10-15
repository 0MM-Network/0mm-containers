# atlas-lean workload image

`localhost/0mm-atlas-lean:local` — CPU workload for C2/C3/C4:

- Lean 4 + Lake (`leanprover/lean4:v4.34.0-rc1`)
- AutoformBot pin `python -m autoform.bot.main`
- APOLLO checkout (`class ApolloRepair` in `/opt/apollo/apollo.py`). Full `import apollo` needs torch — GPU plane, not this image.
- Pantograph `lake exe repl` / `pantograph-repl` (rebuilt against the project toolchain; keep-id readable)
- `leanblueprint`

Not the Pi image. Not CUDA. Not vLLM (I0 serve binds `127.0.0.1:18100` in a **separate** GPU workload).

```text
0mm-containers/atlas-lean/build.sh
```

Pins: `VERSION_PINS`. Mathlib oleans: `$PROJECT_DIR/cache/lean` (host mount).
Wrapper: `$PROJECT_DIR/tools/atlas-lean-workload-lake`.
Host shim: `$PROJECT_DIR/bin/atlas-lean` (SSOT `0mm-containers/atlas-lean/atlas-lean`)
podman-runs this image with the user `podman.sock` as `CONTAINER_HOST` (same as `bin/pi`).
`--dry-run` prints the launch plan (no `FORCE_HOST_SHIM` required). Default exec is the in-tree Rust CLI (host glibc vs bookworm). `ATLAS_LEAN_FORCE_HOST_SHIM=1` takes the podman path.
In-guest Goss: `0mm-containers/atlas-lean/run-goss.sh`.
