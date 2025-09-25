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

