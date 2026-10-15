# Shipped with public 0mm-containers under bin/lib/salt/ (not the parent monorepo).
# Installed to $BTSTRP_ROOT/bin/lib/salt/ by bootstrap.d/0060.
#
# This file is reference + optional local salt-call file_root material.
# Preferred execution at bootstrap stage: run the shell helper on a TTY:
#   export BTSTRP_ROOT=...
#   $BTSTRP_ROOT/bin/lib/bootstrap_private_subrepo
#
# Env: REPO_URL DEST_DIR GH_USER GH_TOKEN (or prompts). BTSTRP_ROOT required.
# Parent monorepo may later wrap this; bootstrap must not require that monorepo.

{% set root = salt['environ.get']('BTSTRP_ROOT', salt['environ.get']('AI_ROOT', '')) %}
{% set helper = root ~ '/bin/lib/bootstrap_private_subrepo' %}

bootstrap_private_subrepo_prereq:
  cmd.run:
    - name: |
        set -euo pipefail
        ROOT="{{ root }}"
        test -n "$ROOT"
        test -x "{{ helper }}"
        if [[ -f "$ROOT/bin/dev-tools-env" ]]; then
          set +u
          # shellcheck disable=SC1091
          . "$ROOT/bin/dev-tools-env"
          set -u
        fi
        command -v git >/dev/null
        git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null
        git subrepo --version >/dev/null 2>&1 \
          || { echo "ERROR: git subrepo missing — run bin/install-dev-tools first" >&2; exit 1; }
        echo "bootstrap_private_subrepo.sls: prereqs ok root=$ROOT"

bootstrap_private_subrepo_run:
  cmd.run:
    - name: |
        set -euo pipefail
        ROOT="{{ root }}"
        export BTSTRP_ROOT="$ROOT"
        export PATH="$ROOT/bin:$ROOT/bin/lib:/usr/bin:/bin:${PATH:-}"
        if [[ -f "$ROOT/bin/dev-tools-env" ]]; then
          set +u
          # shellcheck disable=SC1091
          . "$ROOT/bin/dev-tools-env"
          set -u
        fi
        if [[ -z "${REPO_URL:-}" || -z "${DEST_DIR:-}" || -z "${GH_USER:-}" || -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
          if [[ ! -t 0 ]]; then
            echo "bootstrap_private_subrepo.sls: set REPO_URL DEST_DIR GH_USER GH_TOKEN or run on a TTY:" >&2
            echo "  export BTSTRP_ROOT=$ROOT" >&2
            echo "  $ROOT/bin/lib/bootstrap_private_subrepo" >&2
            exit 1
          fi
        fi
        "{{ helper }}"
    - require:
      - cmd: bootstrap_private_subrepo_prereq
