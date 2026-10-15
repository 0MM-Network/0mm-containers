@bootstrap @genericity @docs
Feature: Decisions are interrogated then locked into features
  As the principal
  I want each review ID decided before bootstrap implementation
  So that the rewrite is specification-driven

  @decision @open
  Scenario: One review cluster per interrogation turn
    Given open items remain in docs/reviews/2026-08-08-bootstrap-sh-genericity.md
    When the principal is interrogated
    Then one ID or agreed cluster is decided per turn
    And the Decision column is updated in the review
    And matching Gherkin scenarios move from @open to @accepted

  @decision @accepted
  Scenario: bootstrap.sh rewrite may proceed after clusters 1-4 and deny-list
    Given workspace root, seed content, hooks, pi/end, and deny-list are decided
    When the principal authorizes implementation
    Then bootstrap.sh may be rewritten red-to-green against features and deny-list BATS
    And bootstrap.d/00n-*.sh skeletons may be added under 0mm-containers/

  @decision @open
  Scenario: Principal authorizes implementation start
    # Ask explicitly before editing bootstrap.sh
    Given decisions are locked
    When the principal says to implement
    Then the agent rewrites bootstrap.sh and adds package bin/bootstrap.d as specified
