# packer — optional containerized Packer

Used by `ckrd-vps` Floci / OCI smoke (`CKRD_VPS_FLOCI=1`) when a host Packer binary is absent.

```bash
./packer/install.sh   # → localhost/0mm-packer:latest
```

Prefer installing Packer to `~/.local/bin/packer` on asioai for docker-builder access to the
rootless Podman socket (`DOCKER_HOST=unix:///run/user/$UID/podman/podman.sock`).

Reuses the same thin-shim pattern as `aws/` and `terraform/` (OpenTofu). Not LocalStack.
