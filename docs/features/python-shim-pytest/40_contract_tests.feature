# RCA: docs/reviews/2026-08-18-python-shim-pytest-rca.md remedy
@backlog @pending @0mm @python-shim @core @task:python-shim-pytest
Feature: Contract tests lock pytest on the sidecar
  As a maintainer
  I need Goss or Testcontainers plus parent ShellSpec
  So the regression cannot return unnoticed

  @backlog @pending @core
  Scenario: Package contract test runs python -m pytest --version in the image
    Given the locked python-cp or 0mm python image
    When the 0mm-containers contract suite runs
    Then a guest command python -m pytest --version exits 0
    Or the suite fails until the image includes pytest or a documented extra

  @backlog @pending @core
  Scenario: Parent ShellSpec covers the shim
    Given spec/workflow/python_cp_shim_spec.sh or a sibling spec
    When tools/spec-run --backlog includes python-shim pytest examples
    Then an example asserts bin/python -m pytest --version
    And that example stays in spec/backlog.paths until green
