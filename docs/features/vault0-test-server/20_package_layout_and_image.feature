@backlog @0mm @vault0-test-server @image @core
Feature: Test-server package lives under 0mm-containers and extends vault/
  As maintainers of rootless container toolchains
  I want the OpenBao test-server image and contracts in 0mm-containers
  So chef/ never grows a one-off Containerfile for test Vault

  Background:
    Given package law in 0mm-containers/AGENTS.md
    And existing tree 0mm-containers/vault/ (OpenBao Containerfile, entrypoint)
    And pi-ai is the reference for install/goss/testcontainers layout

  @backlog @pending @core
  Scenario: Package layout matches 0mm-containers conventions
    When the vault0-test-server work is implemented
    Then artifacts live under 0mm-containers/vault/ and/or a clearly named subpackage
      # Prefer extend vault/ (test profiles) over a disconnected package
    And the layout includes at least:
      | path | purpose |
      | Containerfile (or target stage) | OpenBao/bao image |
      | install.sh | build image + install shims into $PROJECT_DIR/bin |
      | goss.yaml | in-guest contract |
      | test_shim.sh | layer A shim smoke |
      | run-contract-tests.sh or tests/ | layer B Testcontainers + Goss |
    And no new permanent host apt package for bao is required for tests

  @backlog @pending @core
  Scenario: Image provides bao/vault CLI and server
    Given the test-server image is built (e.g. localhost/ai-openbao-test:local)
    When goss runs in-guest
    Then bao or vault binary exists on PATH
    And `bao version` (or vault version) succeeds
    And the image can run `bao server -dev` or config-based server for tests

  @backlog @pending
  Scenario: OpenBao version is pinned and documented
    When install.sh or Containerfile is read
    Then PRODUCT_VERSION or digest is pinned (not floating :latest only in CI)
    And README documents how to bump the pin

  @backlog @pending
  Scenario: Rootless Podman only
    When the image is built and run
    Then build uses rootless podman (no Docker requirement)
    And no privileged container is required for the default test-server profile

  @backlog @pending
  Scenario: Reuse shared contract libraries
    When layer B tests are added
    Then they import 0mm-containers/test/contract/lib harness helpers
    And they do not fork a second Testcontainers stack inside chef/
