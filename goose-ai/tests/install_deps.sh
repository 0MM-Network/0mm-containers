#!/bin/bash

set -e

TEST_DIR=$(dirname "$0")

mkdir -p "$TEST_DIR/lib"

git clone https://github.com/bats-core/bats-support.git "$TEST_DIR/lib/bats-support" || true

git clone https://github.com/bats-core/bats-assert.git "$TEST_DIR/lib/bats-assert" || true
