@bootstrap @private-subrepo
Feature: Bootstrap prepares git-subrepo so the private helper only prompts
  As a principal
  I want bootstrap.sh to install and verify git-subrepo tooling
  So that I only run bin/bootstrap_private_subrepo and answer prompts

  Scenario: install-dev-tools must provide git-subrepo
    When bootstrap.d/0010-install-dev-tools.sh completes successfully
    Then cache/git-subrepo is present under BTSTRP_ROOT
    And bin/dev-tools-env can put git-subrepo on PATH
    And git subrepo --version succeeds after sourcing dev-tools-env

  Scenario: bootstrap verifies git-subrepo before printing next step
    Given hooks have finished
    When bootstrap continues
    Then it sources or checks dev-tools so git subrepo works
    And it fails the bootstrap if git subrepo is unavailable
    And the operator is not told to manually run install-dev-tools as the happy path

  Scenario: next-step instruction is only the helper
    When bootstrap prints the optional private-tree notice
    Then it tells the operator to run bin/bootstrap_private_subrepo or bin/lib/bootstrap_private_subrepo
    And it states that the helper will prompt for REPO_URL DEST_DIR GH_USER GH_TOKEN when unset
    And it does not require the operator to manually export BTSTRP_ROOT if running from the workspace via the bin shim
      # helper may still export BTSTRP_ROOT from git root / bin parent

  Scenario: helper prompts for all missing private-repo inputs on TTY
    Given the operator runs bin/bootstrap_private_subrepo on a TTY
    And REPO_URL DEST_DIR GH_USER GH_TOKEN are unset
    When the helper starts
    Then it prompts for REPO_URL DEST_DIR GH_USER and GH_TOKEN
    And it loads git-subrepo via bin/dev-tools-env without a separate operator step

  Scenario: helper refuses dirty parent work tree before clone
    Given BTSTRP_ROOT has unstaged or untracked changes
    When the helper runs
    Then it fails before git subrepo clone
    And the error tells the operator to commit or stash
