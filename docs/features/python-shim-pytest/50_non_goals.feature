# RCA: docs/reviews/2026-08-18-python-shim-pytest-rca.md
@backlog @pending @0mm @python-shim @task:python-shim-pytest
Feature: Python sidecar stays control-plane thin
  As a principal
  I do not want pytest support to bloat Pi or add CUDA

  @backlog @pending
  Scenario: pi-ai image still has no apt python3
    When inspecting 0mm-containers/pi-ai/Containerfile
    Then it does not apt-install python3 or pytest

  @backlog @pending
  Scenario: Image has no CUDA or torch
    When inspecting the locked python sidecar Containerfile
    Then it does not install CUDA toolkit or torch

  @backlog @pending
  Scenario: Chef L1 remains chef-owned
    When the shim can run pytest
    Then chef/salt0/tests stay the chef SSOT
    And parent ShellSpec is not a replacement for those tests
