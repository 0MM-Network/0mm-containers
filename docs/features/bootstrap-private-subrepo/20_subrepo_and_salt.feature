@bootstrap @private-subrepo
Feature: git-subrepo is mandatory for private attach
  As a developer syncing Salt logic with upstream
  I need the private tree to be a git-subrepo
  So that pull/push stay first-class with the parent workspace repo

  Scenario: Parent must be a git work tree
    Given BTSTRP_ROOT is not inside a git work tree
    When the helper runs with full env set
    Then it fails and tells the principal to git init or choose a git root

  Scenario: git-subrepo must be on PATH
    Given git subrepo is not available
    When the helper runs
    Then it fails and points at install-dev-tools / dev-tools-env

  Scenario: Clone uses git subrepo clone only
    Given BTSTRP_ROOT is a git root and git subrepo works
    And REPO_URL DEST_DIR GH_USER GH_TOKEN are set
    When the helper succeeds
    Then DEST_DIR contains a .gitrepo file
    And the method is git-subrepo (not a nested long-lived plain clone as the success path)

  Scenario: Salt formula ships under bin/lib/salt in the public package
    Given the 0mm-containers package tree
    Then bin/lib/salt/bootstrap_private_subrepo.sls exists
    And bootstrap.d/0060 installs it to BTSTRP_ROOT/bin/lib/salt/
    And bootstrap does not require the parent monorepo salt/project/states tree

  Scenario: Optional monorepo Salt adapter is thin and late-bound
    Given a parent monorepo may wrap project.bootstrap_private_subrepo
    When that adapter runs
    Then it uses BTSTRP_ROOT/bin/lib/bootstrap_private_subrepo
    And if env is incomplete without TTY it fails with interactive instructions

  Scenario: No product org/repo hard-coded in public package
    When scanning 0mm-containers bin/lib/bootstrap_private_subrepo and 0060 hook
    Then there is no hard-coded taqtiqa-admin or developer.chef URL
