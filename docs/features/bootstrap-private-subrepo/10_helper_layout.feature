@bootstrap @private-subrepo
Feature: Private HTTPS repo attaches as git-subrepo via isolated helper
  As a principal on a bare workspace with public 0mm-containers
  I want a generic helper that clones a private GitHub repo with a PAT
  So that Salt and product trees can evolve upstream via git subrepo pull/push

  # Option A: no hard-coded org/repo. Env or TTY prompt.
  # Install path: bin/lib/ (isolated), not a pile of one-offs in bin/ root only.

  Scenario: Helper ships under package bin/lib
    Given the 0mm-containers package tree
    Then bin/lib/bootstrap_private_subrepo is executable
    And bootstrap.d/0060-bootstrap-private-subrepo.sh installs into BTSTRP_ROOT/bin/lib/

  Scenario: Thin bin shim optional for PATH convenience
    Given the helper is installed under bin/lib/
    Then bin/bootstrap_private_subrepo may exist as a thin exec wrapper to bin/lib/
    And Salt invokes bin/lib/bootstrap_private_subrepo preferentially

  Scenario: Required configuration names
    When reading the helper contract
    Then the following environment variables are supported:
      | name     | purpose                                      |
      | REPO_URL | HTTPS GitHub clone URL                       |
      | DEST_DIR | Relative path under BTSTRP_ROOT              |
      | GH_USER  | GitHub username or x-access-token            |
      | GH_TOKEN | Fine-scoped PAT (or GITHUB_TOKEN alias)      |
      | BTSTRP_ROOT | Workspace git root                        |

  Scenario: Prompt when env unset and TTY present
    Given REPO_URL or DEST_DIR or GH_USER or GH_TOKEN is unset
    And stdin and stdout are a TTY
    When the helper runs
    Then it prompts for each missing value
    And GH_TOKEN input is hidden

  Scenario: Non-interactive failure without env
    Given a required variable is unset
    And there is no TTY
    When the helper runs
    Then it exits non-zero with a message to set env or run on a terminal
