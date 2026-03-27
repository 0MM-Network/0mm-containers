#!/usr/bin/env bats 

@test "error.bats passes" {
  bats test/unit/error.bats
}

@test "prereqs.bats passes" {
  bats test/unit/prereqs.bats
}

@test "subuid.bats passes" {
  bats test/unit/subuid.bats
}

@test "load.bats idempotent" {
  source test/unit/load.bats
  source test/unit/load.bats
}