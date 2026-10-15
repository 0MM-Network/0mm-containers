@bootstrap @genericity
Feature: Package AGENTS.md requires bootstrap genericity
  As an agent working in 0mm-containers
  I want package law to state that bootstrap seed and script stay product-agnostic
  So that future edits do not re-introduce parent monorepo coupling

  # Review: P3 — explanation for principal (Q25)
  # Purpose: AGENTS.md is what agents read first in this tree. A short rule
  # "bootstrap must stay generic" + pointers to the review/features stops the
  # next editor from "helpfully" pasting ai-monorepo law back into bootstrap.sh.
  # It is documentation law, not the deny-list and not runtime behavior.

  @decision @accepted @core
  Scenario: 0mm-containers AGENTS.md states genericity rule
    When reading 0mm-containers/AGENTS.md
    Then it requires bootstrap.sh and any seeded parent AGENTS.md to stay product-agnostic
    And it points at docs/reviews/2026-08-08-bootstrap-sh-genericity.md or docs/features/bootstrap-genericity/
    # Already present from review scaffold; Q25 explained — keep
