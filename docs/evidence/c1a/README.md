# C1a evidence

Scrubbed transcripts for the C1a pull request (`bin/0mm-run`, ADR 0002). Host paths read `<home>`, the caller's user name reads `<user>`, and temporary paths read `<bats-tmp>`. No transcript holds a secret.

## Unit, red then green

| File | Commit | Result |
|------|--------|--------|
| `unit-red-361012a.log` | `test:` contract suite, no dispatcher | 29 of 29 not ok, `bin/0mm-run` missing |
| `unit-green-539d5c7.log` | `feat:` dispatcher | 29 of 29 ok |
| `unit-red-0a8d066.log` | `test:` FIFO case | case 8 not ok, a FIFO was mounted |
| `unit-green-b89ecd8.log` | `fix:` files and directories only | 29 of 29 ok |

## Live, on the target host at `b89ecd8`

Rootless podman 5.4.2 with crun, run as the owning bot's host user in a disposable verify clone. `backend.log` records `podman info` reporting rootless `true`.

| Lane | File | Pass rule | Result |
|------|------|-----------|--------|
| unit | `unit.log` | `bin/bats test/unit/0mm_run_contract.bats` all ok | pass, 29 ok |
| You see | `you-see-echo.log` | prints `hello`, exit 0 | pass |
| 1 | not run | needs the private parent repo's trunk shim | not run |
| 2 | `work-mount.log` | marker listed in `/work`, owned by the caller | pass, uid matches |
| 3 | `ro-mounts.log` | only `/work` and `/tmp` writable | pass |
| 4 | `privileged.log` | exit 2, `podman ps -a` count unchanged | pass |
| 5 | `capadd.log` | exit 2, no container | pass |
| 6 | `rootful.log` | `CONTAINER_HOST` at an absent socket refused | pass, `podman unavailable` |
| 7 | `host-access.log` | `network = "host"` and the user podman socket both refused | pass |
| 8 | `caps.log` | `CapEff` all zero, `NoNewPrivs` 1 | pass |
| 9 | `env.log` | `FAKE_TOKEN` absent in the container | pass, names only listed |
| 10 | `reserved-runtime.log` | `runtime krun is reserved` | pass |
| perf | `perf.log` | dispatcher before exec at most 50 ms | pass, median 8 ms (fake podman) |

The perf trunk baseline needs the parent repo's trunk shim, so the head-versus-trunk rule is not run. `perf.log` records the head median wall time for a real `true` run as context.
