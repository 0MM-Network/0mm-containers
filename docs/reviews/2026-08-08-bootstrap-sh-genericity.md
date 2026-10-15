# Critical review: `bootstrap.sh` genericity

**Date:** 2026-08-08  
**Subject:** `0mm-containers/bootstrap.sh` and the seeded parent `AGENTS.md` heredoc  
**Criterion:** Script + seed must be **fully generic**. Nothing specific to a parent product monorepo (e.g. the “ai” Math/Lean workspace) may live in this package’s bootstrap.  
**Status:** Decisions locked; **implementation landed** in `bootstrap.sh`, `bin/`, `bootstrap.d/` (deny-list BATS green).  
**Package law:** `AGENTS.md` (this tree).

---

## Verdict

**Fail** against the genericity criterion. Both the **AGENTS.md heredoc** and the **post-seed host prep** encode a specific parent product’s constitution and bring-up (hardware envelope, Lean-adjacent bans, Salt domains, ShellSpec layout, xAI secrets, default `~/src/ai`).

---

## ID scheme

| Prefix | Area |
|--------|------|
| **H-*** | Seeded `AGENTS.md` heredoc |
| **S-*** | Script behavior (non-heredoc) |
| **P-*** | Process / testing / drift |

Each ID maps to one or more scenarios in `docs/features/bootstrap-genericity/`.  
**Decision log:** fill “Decision” rows when principal answers interrogation; encode in Gherkin + BATS.

---

## H — Heredoc content

| ID | Severity | Finding | Generic? | Decision (fill in) |
|----|----------|---------|----------|-------------------|
| H1 | High | §1 hardware: dual RTX 3060, 24 GB VRAM, 32 GB RAM | No | **DECIDED Q4=B:** one-liner respect host resource limits; **no** SKUs/VRAM/RAM figures |
| H2 | High | §1 ops: Rust/Candle, Python training-in-containers product stack | No | **DECIDED Q5=B:** prefer containers for heavy toolchains only; no named ML stacks |
| H3 | High | §2 `.pi/extensions/*`, backlog footer, roadmap authority | No | **DECIDED Q6=B:** nested AGENTS under `.pi/` if present; **backlog-view extension required**; no footer//backlog UX prose |
| H4 | High | §3 bans permanent “Lean/Pi” toolchains as host law | Partial | **DECIDED Q7=C:** no permanent host language toolchains (containers+shims); **no Lean/lake names** |
| H5 | High | §4 cites parent `docs/adr/0002-…`, `bin/shellspec`, … | No | **DECIDED Q8=D:** ADR **best-practice conventions** (no hard-coded parent ADR filename); see H6 |
| H6 | High | §5 mandates host ShellSpec `spec/` + BATS `test/` | No→Yes as policy | **DECIDED Q8=D:** **ShellSpec + BATS required** (bash-oriented agent); not optional omit |
| H7 | Med | §7 Pi extension UX `/backlog`, footer provenance | No | **DECIDED** with H3 — no deep UX; backlog-view required only |
| H8 | High | §8.6 shims list includes **lake** | No | **DECIDED** with H4 — no lake/Lean; no parent toolchain menu |
| H9 | High | Default `PROJECT_DIR=${HOME}/src/ai` … | No | **DECIDED:** **`BTSTRP_ROOT`** layouts (cluster 1) |
| H10 | Med | Seed titled “monorepo” constitution | Partial | **DECIDED:** frame as **BTSTRP_ROOT workspace**, not product monorepo mission |
| H11 | Med | Nested table only `0mm-containers` + `.pi/extensions` | Partial | **DECIDED Q9=B:** nested AGENTS only; **no** dedicated `0mm-containers/AGENTS.md` pointer section |
| H12 | Low | “sync bootstrap.sh HEREDOC” | Process smell | **DECIDED Q11=A:** **drop** sync instruction |
| H13 | — | Clobber safety: only seed if missing | Yes | **DECIDED Q10=A:** **keep** |

### Heredoc — accepted section list (Q12=C, no line cap)

1. BTSTRP_ROOT workspace identity  
2. Host resource limits (one-liner)  
3. Containers for heavy toolchains  
4. Nested AGENTS.md routing (packages and `.pi/`)  
5. backlog-view extension required  
6. Hard constraints (Podman, shims, cache, no permanent host language toolchains)  
7. ADR best-practice conventions  
8. Test-first: ShellSpec and BATS required  
9. Style (short standing bullets)  
10. Optional one-off bootstrap checklist (removable)  

---

## S — Script body

| ID | Severity | Finding | Generic? | Decision |
|----|----------|---------|----------|----------|
| S1 | High | Calls `./bin/install-dev-tools` + `dev-tools-env` | No | **DECIDED Q13=B:** not inlined; only via **bootstrap.d** after materialize from package |
| S2 | High | Calls `./tools/ensure-host-salt` | No | **DECIDED Q14=B:** hook under `0mm-containers/bootstrap.d/`; hook installs to `$BTSTRP_ROOT/bin` |
| S3 | High | Calls `./bin/salt-apply --domain project tools.goss` | No | **DECIDED Q15=B:** same pattern as S2 — package `bootstrap.d` → `$BTSTRP_ROOT/bin` |
| S4 | High | Hard-codes `pi_XAI_API_KEY` / `XAI_API_KEY` | No | **DECIDED Q18=C:** no secrets in bootstrap; **SaltStack secrets = backlog** (`70_secrets_salt_backlog.feature`) |
| S5 | Med | Always `exec bin/pi` as sole success path | Product-shaped | **DECIDED Q19=A+Q20=C:** after hooks, `exec $BTSTRP_ROOT/bin/pi` **with no args** if present; else exit 0 + message |
| S6 | Low | Optional `pi-ai/install.sh` if present | OK if optional | **Superseded:** numbered `bootstrap.d/00N-pi.sh` + `0mm-containers/bin` |
| S7 | Med | Fail message only mentions pi-ai install | Narrow | **DECIDED:** Pi via numbered hook; missing pi after hooks = exit 0 |
| S8 | High | Default workspace `~/src/ai` (same as H9) | No | **DECIDED:** same as H9 |
| S9 | Med | Env name `PROJECT_DIR` implies AI product | Naming | **DECIDED:** **`BTSTRP_ROOT`** |

### Script — target shape (decided through cluster 3)

1. Resolve **`BTSTRP_ROOT`** (cluster 1)  
2. Seed AGENTS if missing (cluster 2 content)  
3. **Materialize** minimum defaults from `0mm-containers/bin` → `$BTSTRP_ROOT/bin` and `0mm-containers/bootstrap.d` → `$BTSTRP_ROOT/bootstrap.d`  
4. Run **`$BTSTRP_ROOT/bootstrap.d/00*-*.sh`** sorted by name (`00<n>-<bin_name>.sh`); hook failure **aborts**  
5. All installs (incl. Pi) are those hooks; Pi assets from **`0mm-containers/bin`**  
6. **No secrets** in bootstrap (SaltStack secrets backlog)  
7. End: **`exec $BTSTRP_ROOT/bin/pi`** (no args) if executable; else **exit 0** + short message  

**Package ships:** `bootstrap.sh`, `bin/**`, `bootstrap.d/**` (create trees as implementation lands).  

### Decision log

| Date | Cluster | Summary |
|------|---------|--------|
| 2026-08-08 | 1 workspace root | **BTSTRP_ROOT**; layouts; ban `~/src/ai` / `PROJECT_DIR` |
| 2026-08-08 | 2 seed AGENTS | Q4–Q12; ShellSpec/BATS; backlog-view; sections list |
| 2026-08-08 | 3 host prep | Materialize `bin`+`bootstrap.d`; hooks only; salt/dev-tools as hooks→bin |
| 2026-08-08 | 4 pi/secrets/end | Numbered `00n-name.sh` installs; hook fail aborts; no secrets in bootstrap (Salt backlog); exec pi no args or exit 0 |
| 2026-08-08 | 5 deny-list pause | Explained; hooks must run; P3 kept |
| 2026-08-08 | 5b deny-list accept | **bootstrap.sh only**; token list in feature 50; BATS enforced |
| 2026-08-08 | implement | Generic bootstrap.sh + bin/* + bootstrap.d/00n-*.sh; tools installed to BTSTRP_ROOT/bin via hooks |
| 2026-08-08 | self-copy | bootstrap.sh copies itself to `$BTSTRP_ROOT/bootstrap.sh` (beside `0mm-containers/`) |
| 2026-08-08 | bin/bats | **Backlog:** suite must run via `bin/bats`, not bare `bats` (`80_bin_bats_runner.feature`) |

---

## P — Process

| ID | Severity | Finding | Decision |
|----|----------|---------|----------|
| P1 | High | No automated test that seed lacks banned product tokens | **DECIDED:** deny-list BATS on `bootstrap.sh` (feature 50); red until rewrite |
| P2 | Med | Heredoc drifts from any real parent AGENTS | |
| P3 | Med | Package AGENTS does not require seed genericity | |
| P4 | Low | Review must stay under `0mm-containers/docs/reviews/` | **Done (this file)** |

---

## Forbidden coupling / deny-list — ACCEPTED (bootstrap.sh only)

**Mechanism:** BATS greps **`bootstrap.sh` only** (not `bootstrap.d/`, not `bin/`).  
**Runtime:** unchanged — all present `00n-*.sh` hooks still execute (Q23).  
**Tokens + enforcement:** `docs/features/bootstrap-genericity/50_forbidden_tokens.feature` + `test/unit/bootstrap_genericity.bats`.  
**Status:** **RED** on current `bootstrap.sh` until rewrite removes banned substrings.

### Accepted banned substrings (agent-proposed, principal accepted mechanism 2026-08-08)

`src/ai`, `PROJECT_DIR`, `RTX 3060`, `RTX`, `3060`, `24 GB`, `32 GB`, `VRAM`, `Candle`, `QLoRA`, `qlora`, `math-lean`, `miniF2F`, `minif2f`, `Lean`, `lake`, `XAI_API_KEY`, `pi_XAI`, `salt-apply`, `ensure-host-salt`, `install-dev-tools`, `dev-tools-env`, `/backlog`, `0002-git-subrepo`

### Allowed examples

`BTSTRP_ROOT`, `ShellSpec`, `BATS`, `backlog-view`, `Podman`, `bootstrap.d`, `0mm-containers`, `bin/pi`

See also `55_deny_list_explained.feature`.

---

## Feature backlog map

| Feature file | Covers |
|--------------|--------|
| `10_workspace_root.feature` | H9, S8, S9 |
| `20_seed_agents_content.feature` | H1–H8, H10–H13 |
| `30_host_prep_hooks.feature` | S1–S3, S7 |
| `40_pi_optional.feature` | S4–S6 |
| `50_forbidden_tokens.feature` | deny-list / P1 |
| `60_package_agents_pointer.feature` | P3 |
| `90_decision_process.feature` | interrogation / commit order |

---

## Interrogation protocol

1. Principal answers one open ID (or cluster) at a time.  
2. Agent records **Decision** in this file + encodes **executable** scenario(s) (Gherkin + pending/implementing BATS).  
3. No product implementation in `bootstrap.sh` until the relevant feature is specified and (when automated) failing.  
4. When all High IDs decided and encoded: implement red→green inside this package only.

---

## Revision history

| Date | Note |
|------|------|
| 2026-08-08 | Initial review persisted; feature backlog scaffolded |
