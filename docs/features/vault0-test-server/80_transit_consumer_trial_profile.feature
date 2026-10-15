@backlog @0mm @vault0-test-server @transit0 @trial @e2e @core
Feature: Test-server transit-consumer profile for Transit0 trial migration
  As chef and monorepo migration authors
  I need vault0-test-server to run as a disposable transit seal consumer
  So the isolated live e2e path trials Vault0's future seal shape before host data moves

  # Cross-cut SSOT: docs/features/vault0-transit0/migration/70_trial_migrate_e2e_test_server.feature
  # This file is the 0mm package refinement — must not contradict monorepo migration/70.
  #
  # NOT a seal parent: Transit0 remains separate durable identity.

  Background:
    Given vault0-test-server isolation defaults from feature 10 apply
    And Transit0 may be running on non-host-VIP loopback coordinates
    And host Vault0 may use 127.0.0.100:8200

  @backlog @pending @core @trial @lifecycle
  Scenario: Profile transit-consumer is explicit opt-in
    When start runs without --profile=transit-consumer
    Then the server does not require Transit0
    And default dev or init-unseal profiles remain available

  @backlog @pending @core @trial @lifecycle
  Scenario: Profile transit-consumer configures seal.transit
    Given Transit0 is reachable and a trial seal token is provided to the orchestrator
    When I run `vault0-test-server start --profile=transit-consumer`
    Then the instance server config uses seal.transit.address = Transit0 API
    And storage remains under test state dir not host VAULT_ZERO_HOME
    And API URL is not http://127.0.0.100:8200

  @backlog @pending @core @trial @isolation
  Scenario: Fail closed if Transit0 address looks like host Vault0
    Given trial env sets Transit0 address to http://127.0.0.100:8200
    When start --profile=transit-consumer runs
    Then it exits non-zero before creating the consumer
    And stderr cites isolation / wrong seal parent coordinates

  @backlog @pending @core @trial @lifecycle
  Scenario: Restart auto-unseals when Transit0 healthy
    Given a transit-consumer instance was unsealed once
    When the container is restarted with same storage and Transit0 up
    Then ready/status reports unsealed without injecting shamir keys

  @backlog @pending @core @trial @lifecycle
  Scenario: Cold start sealed when Transit0 down
    Given Transit0 is stopped
    When transit-consumer starts cold with existing storage
    Then the instance does not become unsealed
    And status names seal parent unavailable

  @backlog @pending @trial @lifecycle
  Scenario: Stop still destroys ephemeral consumer by default
    Given transit-consumer started without --keep
    When stop runs
    Then container and default test storage are removed
    And Transit0 durable volume is not removed

  @backlog @pending @trial @chef
  Scenario: Factory-live can target transit-consumer profile
    When chef factory-live transit trial is enabled
    Then it starts vault0-test-server --profile=transit-consumer (or equal)
    And it performs SSOT marker put/get and preferred restore dance under that instance
    And it never opens host 127.0.0.100:8200
