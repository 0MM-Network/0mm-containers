# 0mm-containers

Rootless Podman images, shims, contract tests, and **workspace bootstrap**.

Package law: [`AGENTS.md`](./AGENTS.md).

## Workspace bootstrap (operator runbook)

From a **git workspace root** that contains this package as `0mm-containers/`:

### 1. Run public bootstrap

```bash
cd /path/to/workspace          # must be a git root for private subrepo later
./0mm-containers/bootstrap.sh
```

Bootstrap will:

- Set **`BTSTRP_ROOT`** to the workspace root (parent of `0mm-containers/`)
- Materialize `bin/` and `bootstrap.d/` (including `bin/lib/…`)
- Run hooks (including **0010** → install **git-subrepo** under `cache/`)
- **Verify** `git subrepo --version` (fails if missing)
- Print an optional next step for a private product tree
- Optionally `exec bin/pi` if present (exit Pi before step 2 if needed)

You should **not** need to manually run `. bin/dev-tools-env` or `git subrepo --version` on the happy path.

### 2. Optional — attach a private repo (git-subrepo)

```bash
cd /path/to/workspace
./bin/bootstrap_private_subrepo
```

The helper **prompts** (on a TTY) for any unset:

| Variable   | Meaning |
|------------|---------|
| `REPO_URL` | HTTPS URL, e.g. `https://github.com/org/private.git` |
| `DEST_DIR` | Relative path under the workspace, e.g. `chef` |
| `GH_USER`  | GitHub username or `x-access-token` |
| `GH_TOKEN` | Fine-scoped PAT (input hidden); aliases: `GITHUB_TOKEN` |

Or export those variables first for non-interactive use.

This runs **`git subrepo clone`** only (not a long-lived nested clone as the success path).

**Parent repo must be clean** before clone (`git status` empty). Commit or stash monorepo changes first — otherwise git-subrepo errors with `Can't clone subrepo. Unstaged changes`.

After attach, follow the **private repo’s own README** for Salt/product steps.

Day-2 sync (example):

```bash
cd /path/to/workspace
. bin/dev-tools-env
git subrepo pull chef          # or your DEST_DIR
# Host only. dev-tools-env does NOT wrap git (avoids wedging Pi /backlog ShellSpec).
# Always-prompt push:
./bin/git-subrepo-push chef
```

### What bootstrap does *not* do

- Does **not** call Salt (`salt-project-apply` / monorepo states)
- Does **not** auto-clone your private repo
- Does **not** embed org/repo names (generic helper only)

### Layout after bootstrap

```text
$BTSTRP_ROOT/
  bootstrap.sh                 # copy beside 0mm-containers/
  bin/bootstrap_private_subrepo
  bin/lib/bootstrap_private_subrepo
  bin/lib/salt/bootstrap_private_subrepo.sls
  bin/dev-tools-env
  cache/git-subrepo/           # from hook 0010
  0mm-containers/
```

## Specs and tests

| Kind | Path |
|------|------|
| Private-subrepo Gherkin | `docs/features/bootstrap-private-subrepo/` |
| Bootstrap genericity Gherkin | `docs/features/bootstrap-genericity/` |
| BATS | `test/unit/bootstrap_private_subrepo.bats`, `test/unit/bootstrap_genericity.bats` |

```bash
cd 0mm-containers
bats test/unit/bootstrap_private_subrepo.bats
bats test/unit/bootstrap_genericity.bats
# Prefer workspace bin/bats after bootstrap when available
```

## Contract testing (images)

See `docs/adr/0001-container-contract-testing.md` and `test/contract/`.
