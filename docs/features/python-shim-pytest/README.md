# Feature backlog: control-plane Python pytest

**RCA:** [`docs/reviews/2026-08-18-python-shim-pytest-rca.md`](../../reviews/2026-08-18-python-shim-pytest-rca.md)  
**Law:** package `AGENTS.md` + parent ADR 0006.  
**Do not lose:** listed in parent `spec/backlog.paths`.

Trigger: host-nomad S1 could not run `chef/salt0` pytest via `bin/python`.

| File | RC |
|------|-----|
| `10_single_image_contract.feature` | RC1, RC5 |
| `20_pytest_module_on_work_tree.feature` | RC2, RC3 |
| `30_shebang_and_path.feature` | RC4 |
| `40_contract_tests.feature` | remedy tests |
| `50_non_goals.feature` | ADR 0006 |

Tags: `@backlog @pending @0mm @python-shim @core`
