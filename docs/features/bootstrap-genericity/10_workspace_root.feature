@bootstrap @genericity
Feature: Workspace root resolution is product-agnostic
  As a consumer of 0mm-containers on any host project
  I want bootstrap to resolve a workspace root without assuming ~/src/ai
  So that the package does not encode a parent monorepo path

  # Review: H9, S8, S9 — DECIDED 2026-08-08
  # Principal: Q1=A (+ BTSTRP_ROOT), Q2=C (script at BTSTRP_ROOT continues), Q3=D (BTSTRP_ROOT)

  @decision @accepted @core
  Scenario: Canonical env var is BTSTRP_ROOT
    Given the workspace root environment variable is named BTSTRP_ROOT
    When bootstrap resolves the workspace root
    Then it honors BTSTRP_ROOT when set
    And it does not require PROJECT_DIR
    And seeded AGENTS.md refers to BTSTRP_ROOT (not PROJECT_DIR)

  @decision @accepted @core
  Scenario: Script inside 0mm-containers uses parent as BTSTRP_ROOT
    Given BTSTRP_ROOT is unset
    And bootstrap.sh is located at "<workspace>/0mm-containers/bootstrap.sh"
    And directory "<workspace>/0mm-containers" exists
    When bootstrap resolves the workspace root
    Then the workspace root is "<workspace>"
    And that value is the effective BTSTRP_ROOT

  @decision @accepted @core
  Scenario: Running from package copies bootstrap.sh next to 0mm-containers
    Given bootstrap.sh is executed from "<workspace>/0mm-containers/bootstrap.sh"
    When bootstrap resolves BTSTRP_ROOT to "<workspace>"
    Then it copies itself to "<workspace>/bootstrap.sh"
    And "<workspace>/bootstrap.sh" is executable

  @decision @accepted @core
  Scenario: Script copied next to 0mm-containers continues with that folder as BTSTRP_ROOT
    Given BTSTRP_ROOT is unset
    And bootstrap.sh is located at "<workspace>/bootstrap.sh"
    And directory "<workspace>/0mm-containers" exists
    When bootstrap resolves the workspace root
    Then the workspace root is "<workspace>"
    And bootstrap continues (does not error solely due to not living under 0mm-containers/)

  @decision @accepted @core
  Scenario: Invalid layout errors with copy instruction
    Given BTSTRP_ROOT is unset
    And bootstrap cannot find a sibling or child 0mm-containers directory relative to the script
    When bootstrap resolves the workspace root
    Then it exits non-zero
    And the error instructs that bootstrap.sh must be copied into the folder containing 0mm-containers
    And it does not default to "$HOME/src/ai"

  @decision @accepted @core
  Scenario: No hard-coded product home path
    When inspecting bootstrap.sh source and default resolution logic
    Then it does not contain the substring "src/ai" as a default workspace path
