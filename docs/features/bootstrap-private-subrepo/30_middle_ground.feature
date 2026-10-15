@bootstrap @private-subrepo
Feature: Bootstrap ends with optional private-repo instruction only
  As a principal using public 0mm-containers bootstrap
  I want a single clear next step for optional private git-subrepo attach
  So that private product trees stay loosely coupled (no auto Salt, no auto clone)

  # Middle ground: 0060 installs helper; bootstrap echoes how to run it;
  # principal runs helper; private repo README owns further steps.

  Scenario: bootstrap does not invoke Salt for private subrepo
    When inspecting package bootstrap.sh
    Then it does not call salt-project-apply
    And it does not reference host.bootstrap_private_subrepo
    And it does not reference project.bootstrap_private_subrepo

  Scenario: bootstrap does not auto-clone a private repo
    When bootstrap.sh finishes host prep hooks
    Then it has not run bootstrap_private_subrepo as a forced clone step
    And 0060 only installs bin/lib helper (+ shim)

  Scenario: bootstrap prints one optional next-step block
    Given bootstrap reaches end of prep (before optional exec pi)
    When the operator reads stderr or stdout end messages
    Then a short notice mentions optional private product tree
    And the notice includes bin/lib/bootstrap_private_subrepo
    And the notice mentions REPO_URL or prompts
    And the notice tells the operator to follow the private repo README after attach

  Scenario: private repo remains loosely coupled
    Given the public bootstrap has finished
    Then further Salt formulas and product layout come from the private repo documentation
    And public bootstrap does not embed private org or repo names
    And any Salt .sls for private attach is under bin/lib/salt/ on the workspace
    And bootstrap does not apply monorepo salt/project/states for private attach
