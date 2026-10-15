# RCA: docs/reviews/2026-08-18-python-shim-pytest-rca.md RC4
@backlog @pending @0mm @python-shim @core @task:python-shim-pytest
Feature: Nested Pi can run python without /usr/local/bin/python
  As an agent
  I need scripts that say python3 or python -m pytest to work
  So chef .pytest-pkgs shebangs and similar do not hard-fail

  Background:
    Given the Pi image does not apt-install python3
    And /usr/local/bin/python may be absent on the guest

  @backlog @pending @core
  Scenario: PATH python3 is the sidecar shim
    When which python3
    Then it resolves to $PROJECT_DIR/bin/python3
    And python3 --version exits 0

  @backlog @pending
  Scenario: Documented chef L1 command does not require /usr/local/bin/python
    When reading 0mm-containers python-shim docs
    Then the prescribed command is bin/python -m pytest with PYTHONPATH
    And docs do not prescribe shebang /usr/local/bin/python as the only way

  @backlog @pending
  Scenario: Optional shebang compatibility
    Given a script with shebang /usr/local/bin/python
    When that path is missing
    Then either a guest shim exists at /usr/local/bin/python pointing at bin/python
    Or the failure message names bin/python -m pytest as the replacement
