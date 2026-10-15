@bootstrap @genericity @docs
Feature: Deny-list purpose (principal education + decision gate)
  As the principal
  I want a clear explanation of what a bootstrap deny-list is for
  Before I accept automated bans or a rewrite gate

  # Cluster 5 — Q22/Q24 paused for understanding (2026-08-08)

  @decision @accepted
  Scenario: What the deny-list is
    Given bootstrap.sh must stay product-agnostic
    Then a deny-list is a set of substrings that must not appear in agreed files
    And its only job is to fail a test if someone re-introduces parent-product coupling
    And it is not a runtime filter and does not change how hooks execute

  @decision @accepted
  Scenario: What the deny-list is not
    Then the deny-list does not install or remove packages
    And it does not decide BTSTRP_ROOT
    And it does not replace bootstrap.d
    And it does not block legitimate generic words unless we list them

  @decision @accepted
  Scenario: Why it was proposed
    Given the critical review found strings like src/ai, RTX 3060, XAI_API_KEY, salt-apply inlined in bootstrap.sh
    Then automated grep in BATS was proposed so the rewrite cannot regress
    And the principal may accept, edit, or reject that mechanism after understanding it

  @decision @open
  Scenario: Principal accepts or rejects deny-list mechanism
    # OPEN — do not enable failing BATS deny-list until principal decides after this explanation
    When the principal understands the deny-list
    Then they choose: no deny-list | deny-list on bootstrap.sh only | other scope
