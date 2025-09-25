# Goose AI

This repository contains the Goose script for launching and managing VMs with Cloud Hypervisor.

## Prerequisites

Before running the script or tests, ensure the following dependencies are installed:

- cloud-hypervisor
- virtiofsd
- socat
- dosfstools (provides mkdosfs and mcopy)
- qemu-utils (provides qemu-img)
- curl
- expect
- iproute2 (provides ip)
- wget
- coreutils (provides md5sum)
- openssh-client (provides ssh and ssh-keygen)
- netcat (provides nc)
- procps (provides pkill)

On Ubuntu, install them with:

```
sudo apt update
sudo apt install cloud-hypervisor virtiofsd socat dosfstools qemu-utils curl expect iproute2 wget coreutils openssh-client netcat procps
```

Note: cloud-hypervisor may need to be installed from its official releases or a PPA if not available in the default repositories.

Additionally, for running BATS tests, install bats:

```
sudo apt install bats
```

The tests require sudo privileges for managing network interfaces (e.g., macvtap). To avoid sudo prompts, run the tests as root:

```
sudo bats tests/goose_repl.bats
```

Alternatively, ensure your user has passwordless sudo for the relevant commands.

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
