@bootstrap @genericity
Feature: Host prep materializes package bin/bootstrap.d then runs hooks only
  As a consumer of 0mm-containers
  I want bootstrap to copy default bin and bootstrap.d into BTSTRP_ROOT then run hooks
  So that parent monorepo installers are not inlined in bootstrap.sh

  # Review: S1 S2 S3 S7 — DECIDED 2026-08-08
  # Q13/B Q14/B Q15/B Q16/B Q17/C
  # Distribution: 0mm-containers ships bootstrap.sh, bin/*, bootstrap.d/*

  @decision @accepted @core
  Scenario: Package distributes bootstrap.sh, bin/, and bootstrap.d/
    Given the 0mm-containers package tree
    Then it may ship bootstrap.sh, bin/**, and bootstrap.d/**
    And bootstrap.sh once used at BTSTRP_ROOT can copy default minimum setups from
      0mm-containers/bin and 0mm-containers/bootstrap.d into BTSTRP_ROOT
    # Q13 note — materialize defaults from package

  @decision @accepted @core
  Scenario: Materialize bin and bootstrap.d into BTSTRP_ROOT before hooks
    Given BTSTRP_ROOT is resolved
    And 0mm-containers/bin or 0mm-containers/bootstrap.d exists in the package
    When bootstrap performs host readiness
    Then it copies or merges default minimum files into $BTSTRP_ROOT/bin
    And it copies or merges default minimum files into $BTSTRP_ROOT/bootstrap.d
    And it does not require those trees to pre-exist in the parent product monorepo

  @decision @accepted @core
  Scenario: Host readiness runs only sorted numbered bootstrap.d hooks
    When bootstrap performs host readiness after materialize
    Then it runs executable scripts under $BTSTRP_ROOT/bootstrap.d/ matching 00*-*.sh in sorted order
    And hook basenames match the convention 00<n>-<bin_name>.sh
    And every matching hook present is executed (no silent skip of shipped hooks)
    And bootstrap.sh does not inline calls to install-dev-tools by name
    And bootstrap.sh does not inline calls to ensure-host-salt by name
    And bootstrap.sh does not inline calls to salt-apply by name
    # Q13=B Q14=B Q15=B Q16=B Q21=D naming; Q23=C execute all present hooks

  @decision @accepted @core
  Scenario: install-dev-tools only as hook-delivered tooling
    Then any install-dev-tools behavior is invoked only from a bootstrap.d hook
    And not from a hard-coded path inside bootstrap.sh after materialize
    # Q13=B

  @decision @accepted @core
  Scenario: ensure-host-salt shipped as package hook and installed to bin
    Given package file 0mm-containers/bootstrap.d/ contains a hook that provides ensure-host-salt behavior
    When bootstrap materializes bootstrap.d and runs hooks
    Then that hook is responsible for installing the script to $BTSTRP_ROOT/bin
    And bootstrap.sh does not call tools/ensure-host-salt on the parent tree
    # Q14=B

  @decision @accepted @core
  Scenario: salt-apply shipped as package hook and installed to bin
    Given package file 0mm-containers/bootstrap.d/ contains a hook that provides salt-apply behavior
    When bootstrap materializes bootstrap.d and runs hooks
    Then that hook is responsible for installing the script to $BTSTRP_ROOT/bin
    And bootstrap.sh does not call bin/salt-apply on the parent tree before hooks
    # Q15=B

  @decision @accepted @core
  Scenario: Pi install is a numbered bootstrap.d hook using package bin
    Then Pi installation is performed by a hook named like 00N-pi.sh under bootstrap.d
    And that hook installs Pi using artifacts from 0mm-containers/bin
    And bootstrap.sh does not hard-code a pi-ai-only failure path outside hooks
    # Q17=C + Q21=D — pairs with feature 40
