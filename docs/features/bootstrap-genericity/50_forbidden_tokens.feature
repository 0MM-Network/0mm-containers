@bootstrap @genericity
Feature: Forbidden product tokens never appear in bootstrap.sh
  As package maintainers
  I want an automated deny-list over bootstrap.sh only (including heredoc)
  So that parent monorepo specifics cannot regress into the seed script

  # DECIDED 2026-08-08 — Q22: bootstrap.sh only; token list below (principal: use list agent proposes)
  # Q23 runtime hooks are separate (all present hooks execute). Deny-list does NOT scan bootstrap.d.

  @decision @accepted @core
  Scenario: Deny-list scope is bootstrap.sh only
    When the genericity deny-list is applied
    Then only the file bootstrap.sh (package root) is scanned
    And bootstrap.d/** and bin/** are not scanned by this deny-list

  @decision @accepted @core
  Scenario Outline: Banned substrings absent from bootstrap.sh
    When bootstrap.sh is scanned as text
    Then it does not contain the substring "<token>"

    Examples:
      | token             | why |
      | src/ai            | product default path |
      | PROJECT_DIR           | replaced by BTSTRP_ROOT |
      | RTX 3060          | site hardware |
      | RTX               | site hardware SKU family |
      | 3060              | site GPU sku |
      | 24 GB             | site VRAM figure |
      | 32 GB             | site RAM figure |
      | VRAM              | site hardware prose |
      | Candle            | product ML stack |
      | QLoRA             | product train stack |
      | qlora             | product train stack |
      | math-lean         | product domain |
      | miniF2F           | product eval |
      | minif2f           | product eval |
      | Lean              | product language name |
      | lake              | Lean toolchain |
      | XAI_API_KEY       | provider secret |
      | pi_XAI            | provider secret name |
      | salt-apply        | inlined monorepo installer |
      | ensure-host-salt  | inlined monorepo installer |
      | install-dev-tools | inlined monorepo installer name in bootstrap.sh body |
      | /backlog          | extension UX prose |
      | 0002-git-subrepo  | parent ADR filename coupling |

  @decision @accepted @core
  Scenario: Allowed substrings may appear in bootstrap.sh
    Then bootstrap.sh may contain BTSTRP_ROOT
    And bootstrap.sh may contain ShellSpec
    And bootstrap.sh may contain BATS
    And bootstrap.sh may contain backlog-view
    And bootstrap.sh may contain Podman
    And bootstrap.sh may contain bootstrap.d
    And bootstrap.sh may contain 0mm-containers
    And bootstrap.sh may contain bin/pi

  @decision @accepted @core
  Scenario: Deny-list is enforced by package unit tests
    Given the deny-list above is accepted
    Then test/unit/bootstrap_genericity.bats fails when any banned token is present in bootstrap.sh
