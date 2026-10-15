@backlog @0mm @vault0-test-server @chef @core
Feature: Chef live Vault tests consume only the containerized test-server
  As chef vault0 test authors
  I must not open the host production OpenBao from CI or default bats
  So real raft data cannot be wiped by factory-live or apply lifecycle tests

  # Chef remains the consumer; 0mm-containers owns the server image/shims.
  # This feature is the cross-repo contract (implemented when coding starts).

  Background:
    Given host Vault0 may be running with real data
    And vault0-test-server shims are available on PATH via $PROJECT_DIR/bin

  @backlog @pending @core @chef
  Scenario: Live E2E and factory tests require the test-server shim
    When chef enables a live OpenBao test (factory-live, apply lifecycle destructive paths)
    Then the test starts or requires vault0-test-server (or bao-test against it)
    And the test fails closed if only host 127.0.0.100:8200 is reachable
    And VAULT_ZERO_HOME for the test is not the host chef/vault0 path

  @backlog @pending @core @chef
  Scenario: Isolation guard library for chef tests
    Given a shared helper (e.g. chef/test/test_helper.bash or scripts/lib)
    When a live test loads the helper
    Then it rejects VAULT_ADDR containing 127.0.0.100 unless VAULT0_ALLOW_HOST_VAULT=1
    And VAULT0_ALLOW_HOST_VAULT defaults to unset/false and is forbidden in CI
    And rejection message cites 0mm-containers vault0-test-server features

  @backlog @pending @chef
  Scenario: Default bats remain mock-based
    When developers run chef/bin/bats test/vault0_*.bats without live flags
    Then no test starts host openbao or container test-server unless opted in
    And mock PATH stubs remain the default

  @backlog @pending @chef
  Scenario: S6 apply lifecycle tests use container server when they need a real bao
    Given S6 is backlog until this stack exists
    When S6 behavioral tests need a real server
    Then they use vault0-test-server start/seed/stop around assertions
    And they never call vault0-recycle against host ZERO_HOME

  @backlog @pending @chef
  Scenario: Documentation points operators at host units vs test-server
    When chef docs describe day-to-day Vault0
    Then host path remains vault0-openbao + unseal + agent
    And test/CI path is exclusively the containerized test-server shims
