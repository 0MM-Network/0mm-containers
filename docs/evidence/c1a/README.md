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
| 1 | see below | | run at `7ffa96d`, pass |
| 2 | `work-mount.log` | marker listed in `/work`, owned by the caller | pass, uid matches |
| 3 | `ro-mounts.log` | only `/work` and `/tmp` writable | pass |
| 4 | `privileged.log` | exit 2, `podman ps -a` count unchanged | pass |
| 5 | `capadd.log` | exit 2, no container | pass |
| 6 | `rootful.log` | `CONTAINER_HOST` at an absent socket refused | pass, `podman unavailable` |
| 7 | `host-access.log` | `network = "host"` and the user podman socket both refused | pass |
| 8 | `caps.log` | `CapEff` all zero, `NoNewPrivs` 1 | pass |
| 9 | `env.log` | `FAKE_TOKEN` absent in the container | pass, names only listed |
| 10 | `reserved-runtime.log` | `runtime krun is reserved` | pass |
| perf | `perf.log` | dispatcher before exec at most 50 ms | median 8 ms with a fake podman; see below |

The perf trunk baseline needs the parent repo's trunk shim. It was run later, at `7ffa96d` (below).

## Lane 1 and the perf trunk baseline, at `7ffa96d`

Trunk is the parent repo's `main` at `7b3c45e`, in its own disposable verify clone, run through its `bin/python3` shim. Head is `bin/0mm-run` at `7ffa96d`. Both images were cached, and a warm-up run of each was discarded. The timed runs were 20 pairs, interleaved, timed with `date +%s%N`. Another task was using the same host, so expect some noise.

| Lane | File | Pass rule | Result |
|------|------|-----------|--------|
| 1 | `lane1-perf-7ffa96d/regression.log` | trunk prints `1` and head prints `hello`, both exit 0 | **pass** |
| perf | `lane1-perf-7ffa96d/perf.log` | head median at most trunk median + 10 % | **fail**: head 970 ms, trunk 513.5 ms (limit 564.9 ms) |
| perf | `lane1-perf-7ffa96d/perf.log` | dispatcher before exec at most 50 ms | pass with a fake podman, median 13 ms. With real podman the rootless probe alone takes about 880 ms, so the real figure fails |
| context | `lane1-perf-7ffa96d/perf-cold.log` | trunk with `AI_SHIM_WARM=0` (per-call `podman run --rm`) | head 1019.5 ms, trunk 317 ms |
| cause | `lane1-perf-7ffa96d/rootless-probe.log` | where the head time goes | `podman info` median 882 ms; the `podman run` with every floor flag median 192.5 ms |

By default, trunk reuses one warm container and runs `podman exec`. Head starts a new `podman run --rm` on each call. The gap does not come from that, though: trunk's cold path is still faster than head. Most of head's time is the `podman info` rootless check in `bin/0mm-run`, which runs before every exec. The fake podman used for the dispatcher figure answers that call at once, which hides the cost.

The images differ. Trunk runs its CPython image (about 132 MB) and head runs the busybox fixture image (about 9 MB). The plan asks for the same image, but the smaller image only helps head.
