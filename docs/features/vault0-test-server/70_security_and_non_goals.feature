@backlog @0mm @vault0-test-server @security
Feature: Security boundaries and non-goals for the test-server
  As a principal
  I want explicit non-goals so the test-server does not become a second production Vault
  Or a back door into host secret-tool / Agent sinks

  @backlog @pending @security
  Scenario: No host secret-tool or Agent sink coupling
    When the test-server starts
    Then it does not read ~/.config/vault0/agent/token
    And it does not read ~/.config/vault0/credentials/*
    And it does not call secret-tool

  @backlog @pending @security
  Scenario: Test root tokens never written to host production paths
    When start emits a root token for tests
    Then it is stored under a test-only state directory (e.g. under XDG_CACHE_HOME or mktemp)
    And mode is 0600
    And stop deletes it by default

  @backlog @pending @security
  Scenario: Non-goals
    Given the test-server scope
    Then it is not required to provide:
      | non-goal |
      | Host systemd --user vault0-openbao replacement |
      | Production HA raft |
      | Cloud KMS auto-unseal |
      | Salt highstate of desktop secrets |
      | UI parity with host Vault |
      | Sharing storage with host Vault0 |

  @backlog @pending @security
  Scenario: Network exposure is loopback-oriented
    When the test-server publishes a port on the host
    Then binding defaults to 127.0.0.1 not 0.0.0.0
    And documentation warns if a wider bind is requested
