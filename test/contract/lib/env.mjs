/**
 * Point Testcontainers at rootless Podman (user API socket).
 * See docs/adr/0001-container-contract-testing.md
 */
import fs from "node:fs";
import os from "node:os";

export function runtimeDir() {
  return process.env.XDG_RUNTIME_DIR || `/run/user/${os.userInfo().uid}`;
}

export function podmanSocketPath() {
  return process.env.PODMAN_SOCK || `${runtimeDir()}/podman/podman.sock`;
}

/**
 * Mutates process.env for Dockerode/Testcontainers.
 * @throws if the Podman user socket is missing
 */
export function configurePodmanTestcontainers() {
  const sock = podmanSocketPath();
  if (!fs.existsSync(sock)) {
    throw new Error(
      `podman.socket not found at ${sock}. Fix: systemctl --user enable --now podman.socket`,
    );
  }

  process.env.DOCKER_HOST = process.env.DOCKER_HOST || `unix://${sock}`;
  // Ryuk bind-mounts this path on the *engine host*. When tests run inside the
  // pi container, DOCKER_HOST may be unix:///run/podman/podman.sock (guest mount)
  // while the host path remains $XDG_RUNTIME_DIR/podman/podman.sock.
  if (process.env.TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE == null) {
    if (sock === "/run/podman/podman.sock") {
      const hostSock = `${runtimeDir()}/podman/podman.sock`;
      process.env.TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE = hostSock;
    } else {
      process.env.TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE = sock;
    }
  }
  // Rootless Podman: Ryuk needs privileged; suite after() still stops containers.
  if (process.env.TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED == null) {
    process.env.TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED = "true";
  }
  // Nested client (pi guest → host socket): Ryuk port publish is not reachable
  // from inside the agent container. Prefer host runs; disable Ryuk when nested.
  if (
    process.env.TESTCONTAINERS_RYUK_DISABLED == null &&
    (process.env.container === "podman" || sock === "/run/podman/podman.sock")
  ) {
    process.env.TESTCONTAINERS_RYUK_DISABLED = "true";
  }
  if (process.env.TESTCONTAINERS_HOST_OVERRIDE == null) {
    process.env.TESTCONTAINERS_HOST_OVERRIDE = "localhost";
  }

  return { socket: sock, dockerHost: process.env.DOCKER_HOST };
}
