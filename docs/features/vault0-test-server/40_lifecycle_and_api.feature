@backlog @0mm @vault0-test-server @lifecycle @core
Feature: Test-server lifecycle API for automated tests
  As test authors
  I need a stable start/ready/seed/stop interface via shims
  So chef and 0mm contract tests do not hand-roll podman run flags

  Background:
    Given the vault0-test-server shim is installed
    And isolation defaults from feature 10 apply

  @backlog @pending @core @lifecycle
  Scenario: Start prints connection env for tests
    When I run `vault0-test-server start`
    Then the command exits 0 when ready
    And stdout or a state file includes at least:
      | key | meaning |
      | VAULT_ADDR | URL reachable from the test process |
      | VAULT0_TEST_CONTAINER_ID | podman id for cleanup |
      | VAULT0_TEST_ROOT_TOKEN | dev/root token for this ephemeral instance only |
    And those values are not the host production token files under ~/.config/vault0/

  @backlog @pending @core @lifecycle
  Scenario: Status and ready probe
    Given a test-server is running
    When I run `vault0-test-server status`
    Then it reports running and unsealed (or dev-mode ready)
    And `vault0-test-server ready` waits until sys/health is acceptable or times out non-zero

  @backlog @pending @core @lifecycle
  Scenario: Stop removes the container by default
    Given a test-server started without --keep
    When I run `vault0-test-server stop`
    Then the container is removed
    And VAULT_ADDR from that instance no longer answers

  @backlog @pending @lifecycle
  Scenario: Dev mode default for unit tests
    When start runs with defaults
    Then OpenBao/Vault listens in a mode suitable for fast tests
      # e.g. -dev or pre-inited single-unseal test config
    And a root token is available to the orchestrator without host secret-tool

  @backlog @pending @lifecycle
  Scenario: Optional init-unseal profile for integration tests
    When start runs with --profile=init-unseal
    Then the server is initialized and unsealed inside the container
    And unseal/root material is written only to the test state dir (0600)
    And material is deleted on stop unless --keep-secrets

  @backlog @pending @lifecycle
  Scenario: Seed helper for KV test data
    Given a running test-server and root/test token
    When I run `vault0-test-server seed --fixture <path>`
    Or `bao-test kv put` via the CLI shim
    Then KV data is visible only on that test-server
    And host 127.0.0.100:8200 KV is unchanged

  @backlog @pending @lifecycle
  Scenario: Idempotent start
    When start is invoked twice without stop
    Then the second start either no-ops on the same instance or fails clearly
    And it does not create a second container fighting the same ports by default
