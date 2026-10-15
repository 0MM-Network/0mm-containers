@bootstrap @genericity
Feature: Seeded AGENTS.md is a generic workspace constitution
  As a consumer who has no parent AGENTS.md yet
  I want bootstrap to write only agreed product-agnostic agent law
  So that 0mm-containers does not ship another monorepo's mission

  # Review: H1–H8, H10–H13 — DECIDED 2026-08-08
  # Q4/B Q5/B Q6/B(+backlog-view required) Q7/C Q8/D Q9/B Q10/A Q11/A Q12/C

  Background:
    Given AGENTS.md does not exist at BTSTRP_ROOT
    When bootstrap seeds AGENTS.md

  @decision @accepted @core
  Scenario: Hardware is only a resource-limits one-liner
    Then AGENTS.md may say to respect host resource limits
    And AGENTS.md does not name GPU SKUs, VRAM sizes, or system RAM figures
    # H1 / Q4=B

  @decision @accepted @core
  Scenario: Tooling preference is containers for heavy toolchains only
    Then AGENTS.md prefers containers for heavy toolchains
    And AGENTS.md does not name product ML stacks (e.g. Candle, QLoRA, math-lean mission)
    # H2 / Q5=B

  @decision @accepted @core
  Scenario: Nested AGENTS under .pi and backlog-view required
    Then AGENTS.md states that nested AGENTS.md under .pi/ applies when present
    And AGENTS.md states that the backlog-view extension is required
    And AGENTS.md does not document /backlog command UX or footer provenance details
    # H3 H7 / Q6=B — backlog-view required; no deep UX prose

  @decision @accepted @core
  Scenario: No permanent host language toolchains; no Lean/lake names
    Then AGENTS.md states no permanent host language toolchains — containers and thin shims
    And AGENTS.md does not mention Lean or lake
    # H4 H8 / Q7=C

  @decision @accepted @core
  Scenario: ADR best practice and ShellSpec/BATS required
    Then AGENTS.md requires BTSTRP_ROOT to follow ADR best-practice conventions
    And AGENTS.md requires ShellSpec and BATS as host test harnesses
    And AGENTS.md may note the coding agent surface is bash-oriented
    And AGENTS.md does not hard-code a parent monorepo ADR filename (e.g. docs/adr/0002-git-subrepo-tdd-bdd.md)
    # H5 H6 / Q8=D

  @decision @accepted @core
  Scenario: Nested AGENTS routing without 0mm-containers pointer section
    Then AGENTS.md requires reading nested AGENTS.md under package trees
    And AGENTS.md does not include a dedicated pointer section to 0mm-containers/AGENTS.md
    # H11 / Q9=B — package trees still win via nested rule; no special 0mm section

  @decision @accepted @core
  Scenario: Seed never overwrites an existing AGENTS.md
    Given AGENTS.md already exists at BTSTRP_ROOT
    When bootstrap runs
    Then the existing AGENTS.md bytes are unchanged
    # H13 / Q10=A

  @decision @accepted @core
  Scenario: No sync-heredoc-from-living-AGENTS instruction
    Then AGENTS.md does not instruct agents to sync bootstrap.sh HEREDOC from living AGENTS
    # H12 / Q11=A

  @decision @accepted @core
  Scenario: Fixed section list (no line cap)
    Then seeded AGENTS.md contains exactly these section purposes (headings may vary slightly):
      | section |
      | BTSTRP_ROOT workspace identity |
      | Host resource limits (one-liner) |
      | Containers for heavy toolchains |
      | Nested AGENTS.md routing (packages and .pi/) |
      | backlog-view extension required |
      | Hard constraints (Podman, shims, cache, no permanent host language toolchains) |
      | ADR best-practice conventions |
      | Test-first: ShellSpec and BATS required |
      | Style (short standing bullets) |
      | Optional one-off bootstrap checklist (removable) |
    And there is no maximum line count
    # Q12=C
