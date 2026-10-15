@backlog @0mm @vault0-test-server @shim @core
Feature: Sidecar shims expose the test-server like bin/python and bin/bats
  As agents and CI running on host or nested Pi
  I want thin $PROJECT_DIR/bin shims that exec into the OpenBao test image
  So heavy toolchains stay containerized (ADR 0006) with one entry pattern

  # Parent monorepo pattern:
  #   bin/python  → bin/_run <image> python …
  #   bin/bats    → containerized bats
  # Test-server must adopt the same discipline — not host-global bao for tests.

  Background:
    Given $PROJECT_DIR/bin/_run runs commands in a sidecar image
    And nested Pi may set PROJECT_DIR_HOST for host path binds
    And install.sh of the vault package installs shims when $PROJECT_DIR/bin exists

  @backlog @pending @core @shim
  Scenario: Primary lifecycle shim is installed under bin/
    When 0mm-containers vault test-server install.sh succeeds
    Then a shim exists at $PROJECT_DIR/bin/vault0-test-server
      # name may be bao-test-server; document single SSOT name in package README
    And the shim is executable and invokes podman/image via _run or package runner
    And `vault0-test-server --help` documents start stop status addr env

  @backlog @pending @core @shim
  Scenario: CLI shim for bao against the test-server
    When install succeeds
    Then $PROJECT_DIR/bin/bao-test (or vault0-test-bao) runs bao inside the test image
    And it points VAULT_ADDR at the running test-server instance
    And it does not use host /usr/local/bin/bao against 127.0.0.100 unless explicitly forced (forbidden by default)

  @backlog @pending @shim
  Scenario: Shims refuse host production coordinates
    Given VAULT_ADDR=http://127.0.0.100:8200 in the environment
    When bao-test or vault0-test-server starts without --allow-host-vault
    Then the shim exits non-zero with REMEDY to unset VAULT_ADDR
    And --allow-host-vault is not documented for CI (break-glass only, off by default)

  @backlog @pending @core @shim
  Scenario: Nested Pi uses PROJECT_DIR_HOST for volume binds
    Given tests run inside the Pi container with PROJECT_DIR=/work
    When the shim starts a test-server container needing a bind mount
    Then bind sources are host paths via PROJECT_DIR_HOST / _run host_path mapping
    And the shim fails with REMEDY if PROJECT_DIR_HOST is required but missing

  @backlog @pending @shim
  Scenario: verify-shims includes vault test shims
    When bin/verify-shims runs
    Then vault0-test-server and bao-test shims are listed or skipped with explicit reason
    And broken symlinks fail verification

  @backlog @pending @shim
  Scenario: No permanent host OpenBao install required for tests
    Given a clean agent environment with only podman + shims
    When the test-server image is present locally
    Then bats/pytest can exercise bao via bin/bao-test without apt install openbao on the host
