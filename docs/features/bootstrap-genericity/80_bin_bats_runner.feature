@bootstrap @genericity @backlog
Feature: Package unit tests run via bin/bats
  As a principal
  I want the documented and enforced way to run bootstrap genericity tests to be bin/bats
  So that ShellSpec/BATS come from the workspace toolchain, not an ambient host bats

  # Requested 2026-08-08: sequence MUST use bin/bats, not bare `bats` on PATH.

  @decision @accepted @pending @core
  Scenario: Documented command uses bin/bats
    When reading package docs for how to run test/unit/bootstrap_genericity.bats
    Then the prescribed command is equivalent to:
      """
      cd <package-or-BTSTRP_ROOT>
      ./bin/bats test/unit/bootstrap_genericity.bats
      """
    Or with BTSTRP_ROOT set:
      """
      "$BTSTRP_ROOT/bin/bats" "$BTSTRP_ROOT/0mm-containers/test/unit/bootstrap_genericity.bats"
      """
    And docs do not prescribe bare `bats` on PATH as the primary command

  @decision @accepted @pending @core
  Scenario: bin/bats is available after bootstrap materialize and install-dev-tools hook
    Given bootstrap has run hooks including 0010-install-dev-tools
    Then "$BTSTRP_ROOT/bin/bats" is executable
    And it can run test/unit/bootstrap_genericity.bats

  @decision @accepted @pending
  Scenario: Optional package helper invokes bin/bats only
    Given a helper such as test/unit/run.sh or package README script
    When the helper runs the genericity suite
    Then it execs bin/bats (resolved under BTSTRP_ROOT or package-adjacent bin)
    And it fails clearly if bin/bats is missing (tell user to run bootstrap / 0010 hook)
