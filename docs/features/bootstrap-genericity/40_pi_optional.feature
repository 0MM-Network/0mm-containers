@bootstrap @genericity
Feature: Pi and installs via ordered bootstrap.d; secrets deferred
  As a consumer of 0mm-containers
  I want all installs done by numbered bootstrap.d hooks and a simple pi exec
  So that bootstrap.sh stays thin (KIS)

  # Review: S4 S5 S6 Q17 — DECIDED 2026-08-08
  # Q18/C Q19/A(+Q20 no args) Q20/C Q21/D

  @decision @accepted @core
  Scenario: All package installs are ordered bootstrap.d hooks
    Given 0mm-containers/bootstrap.d/ ships install hooks
    Then every install hook file name matches "00<n>-<bin_name>.sh"
    And bootstrap runs $BTSTRP_ROOT/bootstrap.d/00*.sh in sorted name order after materialize
    And bootstrap.sh does not special-case pi-ai/install.sh outside that convention
    # Q21=D — supersedes one-off pi path prose; install/pi.sh becomes e.g. 00N-pi.sh

  @decision @accepted @core
  Scenario: Hook non-zero status aborts bootstrap
    When any executed bootstrap.d hook exits non-zero
    Then bootstrap aborts with non-zero status
    # KIS default under Q21=D

  @decision @accepted @core
  Scenario: No provider secrets in bootstrap.sh
    When inspecting bootstrap.sh source
    Then it does not hard-code XAI_API_KEY or pi_XAI_API_KEY
    And it does not implement secret creation
    # Q18=C — secrets via future system SaltStack (backlog feature, not bootstrap)

  @decision @accepted @core
  Scenario: Secrets integration is a separate backlog feature
    Then a backlog feature tracks system SaltStack secrets integration
    And that work is out of scope for bootstrap.sh genericity rewrite
    # Q18=C — see 70_secrets_salt_backlog.feature

  @decision @accepted @core
  Scenario: Final exec pi without arg passthrough
    Given hooks completed successfully
    And $BTSTRP_ROOT/bin/pi is executable
    When bootstrap reaches end state
    Then it execs $BTSTRP_ROOT/bin/pi with no arguments
    And it does not pass bootstrap "$@" through to pi
    # Q19=A + Q20=C KIS

  @decision @accepted @core
  Scenario: Missing pi after hooks is soft success
    Given hooks completed successfully
    And $BTSTRP_ROOT/bin/pi is not executable
    When bootstrap reaches end state
    Then it exits 0
    And it prints a short message that pi is not available
    # Q19=A else branch
