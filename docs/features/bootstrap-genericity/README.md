# Feature backlog: bootstrap.sh genericity

**Review SSOT:** [`docs/reviews/2026-08-08-bootstrap-sh-genericity.md`](../../reviews/2026-08-08-bootstrap-sh-genericity.md)  
**Subject:** `bootstrap.sh` + seeded parent `AGENTS.md`  
**Law:** package `AGENTS.md` — changes stay under `0mm-containers/`.

## Purpose

Track **principal decisions** from the critical review as **executable features**.  
Scenarios tagged:

| Tag | Meaning |
|-----|---------|
| `@decision` | Awaiting or recording a principal choice |
| `@accepted` | Decision locked; may still be `@pending` for code |
| `@pending` | Not automated green yet |
| `@core` | Must pass before bootstrap rewrite merges |

## Files

| File | Review IDs |
|------|------------|
| `10_workspace_root.feature` | H9, S8, S9 — **DECIDED** `@accepted` |
| `20_seed_agents_content.feature` | H1–H8, H10–H13 — **DECIDED** `@accepted` |
| `30_host_prep_hooks.feature` | S1–S3, S7 — **DECIDED** `@accepted` |
| `40_pi_optional.feature` | S4–S6 — **DECIDED** `@accepted` |
| `70_secrets_salt_backlog.feature` | Q18=C Salt secrets — **backlog** `@pending` |
| `80_bin_bats_runner.feature` | **MUST** run unit suite via **`bin/bats`**, not bare `bats` — **backlog** `@pending` |
| `50_forbidden_tokens.feature` | deny-list **bootstrap.sh only** — **DECIDED**; BATS green |
| `55_deny_list_explained.feature` | what deny-list is |
| `60_package_agents_pointer.feature` | P3 AGENTS pointer — **DECIDED** keep |
| `90_decision_process.feature` | implement **done** (bootstrap.sh + bin + bootstrap.d) |

## Automation

- Gherkin here is the **decision backlog** (human + agent readable).  
- BATS: `test/unit/bootstrap_genericity.bats` — enforces accepted rules when implemented.  
- **Run (required once feature 80 is green):** `bin/bats` only — not bare `bats` on PATH:

```bash
# After bootstrap (install-dev-tools hook → $BTSTRP_ROOT/bin/bats):
"$BTSTRP_ROOT/bin/bats" "${BTSTRP_ROOT}/0mm-containers/test/unit/bootstrap_genericity.bats"
# Or from workspace root if bin/bats is on PATH via $BTSTRP_ROOT/bin:
./bin/bats 0mm-containers/test/unit/bootstrap_genericity.bats
```

Until feature 80 is implemented, agents may still use a temporary bats for development, but the **backlog contract** is `bin/bats`.

## Status legend (features)

- **OPEN** — interrogation not finished  
- **DECIDED** — scenarios `@accepted`; implementation may follow  
- **GREEN** — BATS green for that slice  
