# RCA: docs/reviews/2026-08-18-python-shim-pytest-rca.md RC1 RC5
@backlog @pending @0mm @python-shim @core @task:python-shim-pytest
Feature: bin/python uses one declared control-plane image
  As a principal
  I need bin/python and bin/python3 to exec a single pinned sidecar
  So stock slim-without-pytest and unused python-runner images cannot diverge

  Background:
    Given ADR 0006 keeps CPython out of the Pi image
    And parent bin/python currently calls bin/_run with docker.io/library/python:3.12-slim-bookworm

  @backlog @pending @core
  Scenario: Shim image tag is localhost/ai-python-cp:local or the 0mm-containers package tag
    When reading bin/python
    Then it invokes _run with localhost/ai-python-cp:local
    Or it invokes the documented 0mm-containers python package image
    And it does not hardcode docker.io/library/python:3.12-slim-bookworm as the only runtime

  @backlog @pending @core
  Scenario: Image SSOT is one Containerfile
    Given images/python-cp and 0mm-containers/python both exist
    When the contract is locked
    Then exactly one image is the bin/python runtime
    And the other is deprecated or an explicit alias of the first
