# Goose AI

This repository contains the Goose script for launching and managing VMs with Cloud Hypervisor.

## Running BATS Tests

To run the BATS tests for the Goose script:

1. **Install test dependencies**: Run the installation script to set up bats-support and bats-assert.
   ```
   ./tests/install_deps.sh
   ```

2. **Run the tests**: Execute the BATS test file using the `bats` command (ensure BATS is installed on your system).
   ```
   bats tests/goose_repl.bats
   ```

These tests verify REPL mode and non-REPL command execution, including VM launch and serial interaction.
