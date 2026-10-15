@bootstrap @genericity @backlog
Feature: System SaltStack secrets integration (backlog)
  As a principal
  I want API/provider secrets handled by system SaltStack when integrated
  So that bootstrap.sh never owns secret material

  # Spawned from Q18=C — not part of bootstrap.sh rewrite MVP

  @decision @accepted @pending
  Scenario: Secrets are not created by bootstrap.sh
    When bootstrap runs
    Then it does not create podman secrets or read provider API keys from the environment for storage

  @decision @open @pending
  Scenario: System SaltStack formula manages provider secrets
    Given system SaltStack integration exists for the host
    When secrets are required for Pi or other tools
    Then Salt formulas (not bootstrap.sh) ensure secret presence
    # OPEN: formula names, domains, and timing vs bootstrap.d hooks
