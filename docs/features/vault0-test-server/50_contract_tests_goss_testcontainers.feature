@backlog @0mm @vault0-test-server @contract @core
Feature: Contract tests follow ADR 0001 (shim layer A + Goss/Testcontainers layer B)
  As package maintainers
  I want the same two-layer contract model as pi-ai
  So vault test-server quality is enforceable without host Goss or DinD

  Background:
    Given docs/adr/0001-container-contract-testing.md
    And shared libs under 0mm-containers/test/contract/lib/

  @backlog @pending @core @contract
  Scenario: Layer A — shim smoke without provider APIs
    When test_shim.sh runs
    Then it checks shim syntax and image presence
    And it exercises start/status/stop dry paths or short-lived container
    And it does not require host Vault0 to be up
    And it does not call external cloud APIs

  @backlog @pending @core @contract
  Scenario: Layer B — in-guest Goss via Testcontainers
    When run-contract-tests.sh (or package equivalent) runs
    Then Testcontainers starts the test-server image rootless
    And Goss executes inside the guest validating:
      | check | example |
      | bao/vault binary | exists + version |
      | server can run | dev or config path |
      | isolation env | no mandatory host VIP |
    And containers are cleaned up after the suite

  @backlog @pending @contract
  Scenario: Nested agent contract run is supported or explicitly skipped
    Given tests may run inside Pi with host podman socket
    When contract suite detects nested mode
    Then it uses harness path mapping and Ryuk rules from ADR 0001
    Or skips with a clear message if unsupported (not a silent pass)

  @backlog @pending @contract
  Scenario: Automation entry uses monorepo shims for heavy runners
    When documentation specifies how to run contract tests
    Then Node/python/bats invocations prefer $PROJECT_DIR/bin/* shims
      # e.g. bin/bats, not bare bats; bin/python if pytest used
    And bare host toolchains are not required beyond podman + shim prerequisites
