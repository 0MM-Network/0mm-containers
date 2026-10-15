# Features: bootstrap private git-subrepo helper

| File | Intent |
|------|--------|
| `10_helper_layout.feature` | bin/lib isolation, env/prompt contract |
| `20_subrepo_and_salt.feature` | git-subrepo mandatory; Salt TTY vs env |
| `30_middle_ground.feature` | bootstrap only prints next step; no auto Salt/clone |
| `40_bootstrap_prepares_subrepo_tools.feature` | bootstrap installs/verifies git-subrepo; helper only prompts |

**Executable checks:** `test/unit/bootstrap_private_subrepo.bats`  
**Implementation:** `bin/lib/bootstrap_private_subrepo`  
**Shim:** `bin/bootstrap_private_subrepo`  
**Salt formula (package SSOT):** `bin/lib/salt/bootstrap_private_subrepo.sls`  
**Hook 0060 installs to:** `$BTSTRP_ROOT/bin/lib/…` and `$BTSTRP_ROOT/bin/lib/salt/…`  
**Monorepo:** optional thin adapter only — must not be required at public bootstrap
