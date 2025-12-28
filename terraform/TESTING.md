# Testing Instructions for Rootless Podman Setup

This document provides instructions on how to set up the BATS (Bash Automated Testing System) framework and execute the integration tests for the rootless Podman setup with systemd container and shim.

## Prerequisites
- A Linux system with rootless Podman installed and configured.
- Git for cloning repositories.
- Required files in the working directory: `Containerfile`, `shim.sh`, `nested-podman.service`, `integration-tests.bats`.
- Internet access to pull Docker images (e.g., busybox) and install dependencies.

## Step 1: Install BATS
BATS is required to run the tests. Install it using the following commands:

```
git clone --depth=1 https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
cd ..
```

This installs BATS to `/usr/local`. Ensure `/usr/local/bin` is in your PATH.

Alternatively, on Debian-based systems, you can install via apt (if available in repositories):
```
sudo apt-get update
sudo apt-get install bats
```

## Step 2: Prepare the Environment

- Make sure `shim.sh` is executable:

```bash
chmod +x shim.sh
```

The tests will automatically build the Podman image if it doesn't exist.


## Step 3: Execute All Tests

Run the integration tests using the BATS command:

```
bats integration-tests.bats
```

This will execute all @test blocks in integration-tests.bats. The tests include setup and teardown to manage the container lifecycle.

## Expected Output

- Successful tests will show green checkmarks.
- Failures will display error messages with diagnostics.


## Troubleshooting

- If Podman fails to start containers, ensure your user has rootless Podman enabled (e.g., podman system migrate).
- Check for sufficient subuid/subgid mappings in /etc/subuid and /etc/subgid.
- If systemd doesn't boot within 30 seconds, increase the wait time in the setup function.
- For verbose output, run with --tap or other BATS flags.

Tests are designed to be idempotent and clean up after themselves.


