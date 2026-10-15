# RCA: docs/reviews/2026-08-18-python-shim-pytest-rca.md RC2 RC3
@backlog @pending @0mm @python-shim @core @task:python-shim-pytest
Feature: python -m pytest works on a mounted /work tree
  As an agent inside Pi
  I need bin/python -m pytest to import pytest and see project tests
  So chef/salt0 L1 and other in-tree pytest can run without a host CPython

  Background:
    Given PROJECT_DIR is mounted into the sidecar as /work
    And chef/salt0/.pytest-pkgs may supply pytest on the host tree

  @backlog @pending @core
  Scenario: python -m pytest --version succeeds
    When the operator runs bin/python -m pytest --version
    Then the command exits 0
    And stdout includes a pytest version
    And the process is the sidecar image not a host apt python3

  @backlog @pending @core
  Scenario: PYTHONPATH from the caller reaches the sidecar
    Given PYTHONPATH includes a directory on the work tree that contains pytest
    When bin/python -m pytest --version
    Then import succeeds using that path or the image-bundled pytest
    And missing pytest prints a clear error not /usr/local/bin/python ENOENT

  @backlog @pending @core
  Scenario: bin/pytest shim exists
    When listing parent bin/
    Then bin/pytest is executable
    And it uses the same _run image as bin/python
