@backlog @0mm @vault0-test-server @isolation @core
Feature: Test-server is fully isolated from host Vault0 data plane
  As a principal with a live host OpenBao holding real raft data
  I need every automated test server to be incapable of sharing
  host VIP, host raft path, or host unseal/root material by default

  # Host production (desktop): often 127.0.0.100:8200 + VAULT_ZERO_HOME under chef/
  # Test-server MUST NOT default to those coordinates.

  Background:
    Given a host may already run vault0-openbao on 127.0.0.100:8200
    And host raft may live under $PROJECT_DIR/chef/vault0 or similar
    And the test-server is provided by 0mm-containers

  @backlog @pending @core @isolation
  Scenario: Default listen address is never the host Vault0 VIP
    When the test-server starts with default configuration
    Then it does not bind or advertise http://127.0.0.100:8200
    And its API URL is unique to the container network namespace
      # e.g. 127.0.0.1:<ephemeral host-mapped port> or slirp/pasta URL from podman
    And tests receive VAULT_ADDR only via the shim/orchestrator export

  @backlog @pending @core @isolation
  Scenario: Default storage is ephemeral and outside host raft
    When the test-server starts with default configuration
    Then raft/file storage is under a container volume or mktemp path
    And that path is not $PROJECT_DIR/chef/vault0
    And that path is not $HOME/chef/vault0
    And destroying the container destroys test data (unless explicit keep-volume opt-in)

  @backlog @pending @core @isolation
  Scenario: Fail closed if configuration would target host production coordinates
    Given an operator or test sets VAULT_ADDR to http://127.0.0.100:8200
    Or VAULT_ZERO_HOME to a path matching host chef vault0 storage
    When the test-server shim or harness starts
    Then it exits non-zero before starting bao
    And stderr contains REMEDY naming isolation (use defaults / unset host env)

  @backlog @pending @core @isolation
  Scenario: Host environment does not leak into the test-server by accident
    Given the host shell exports VAULT_ADDR VAULT_TOKEN VAULT_ZERO_HOME for production
    When the shim starts the test-server without explicit passthrough flags
    Then the container does not receive host VAULT_TOKEN or host unseal material
    And the container VAULT_ADDR is the test-server address not the host VIP

  @backlog @pending @isolation
  Scenario: Parallel test-servers do not clash
    When two test-server instances start concurrently
    Then each has distinct published ports and storage directories
    And stopping one does not stop the other
