/**
 * Shared Testcontainers harness for 0mm-containers contract tests.
 * Orchestrates lifecycle + mounts; Goss performs in-guest assertions.
 */
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { GenericContainer, Wait } from "testcontainers";
import { configurePodmanTestcontainers } from "./env.mjs";
import { ensureGossBinary, defaultAiRoot } from "./goss-bin.mjs";

/**
 * Map a path as seen by this process to the path the Podman *engine* must bind.
 * When contract tests run inside the pi guest, client paths like /work/... are
 * not valid on the host — resolve via `podman inspect` mounts.
 */
export function resolveEnginePath(clientPath) {
  const abs = path.resolve(clientPath);
  const nested =
    process.env.container === "podman" || fs.existsSync("/run/.containerenv");
  if (!nested) {
    return abs;
  }
  try {
    const cid = (process.env.HOSTNAME || fs.readFileSync("/etc/hostname", "utf8")).trim();
    const raw = execFileSync(
      "podman",
      ["inspect", cid, "--format", "{{json .Mounts}}"],
      { encoding: "utf8" },
    );
    const mounts = JSON.parse(raw);
    let best = null;
    for (const m of mounts) {
      const dest = m.Destination || m.destination;
      const src = m.Source || m.source;
      if (!dest || !src) continue;
      if (abs === dest || abs.startsWith(`${dest}/`)) {
        if (!best || dest.length > best.dest.length) {
          best = { dest, src };
        }
      }
    }
    if (best) {
      const rel = abs.slice(best.dest.length).replace(/^\//, "");
      return rel ? path.posix.join(best.src, rel) : best.src;
    }
  } catch {
    // fall through
  }
  return abs;
}

/**
 * GenericContainer + rootless Podman defaults (keep-id, label disable).
 * UsernsMode is not exposed as a with* helper in testcontainers@11.
 */
class RootlessPodmanContainer extends GenericContainer {
  constructor(image) {
    super(image);
    this.hostConfig.UsernsMode = "keep-id";
  }
}

/**
 * @typedef {object} ContractOptions
 * @property {string} image
 * @property {string} workDir           Host dir bind-mounted at /work
 * @property {string|string[]} gossFiles Absolute path(s) to goss YAML on the host
 * @property {Record<string,string>} [env] Extra env injected into the guest
 * @property {string} [home=/home/node] HOME inside the guest
 * @property {string} [user]            USER env (defaults to host user)
 * @property {number} [startupMs]
 */

/**
 * Start one long-lived container for a suite. Caller must stop() in after().
 * @param {ContractOptions} opts
 */
export async function startContractContainer(opts) {
  configurePodmanTestcontainers();

  const aiRoot = defaultAiRoot();
  const gossBin = await ensureGossBinary(aiRoot);
  const workDir = path.resolve(opts.workDir);
  fs.mkdirSync(workDir, { recursive: true });

  const gossList = (Array.isArray(opts.gossFiles) ? opts.gossFiles : [opts.gossFiles]).map((p) =>
    path.resolve(p),
  );
  for (const g of gossList) {
    if (!fs.existsSync(g)) {
      throw new Error(`goss file missing: ${g}`);
    }
  }

  const home = opts.home ?? "/home/node";
  const user = opts.user ?? process.env.USER ?? "node";
  const env = {
    HOME: home,
    USER: user,
    ...(opts.env || {}),
  };

  /** @type {{ source: string, target: string, mode?: string }[]} */
  const binds = [
    { source: resolveEnginePath(workDir), target: "/work", mode: "rw" },
    { source: resolveEnginePath(gossBin), target: "/opt/contract/goss", mode: "ro" },
  ];
  gossList.forEach((g, i) => {
    const name = path.basename(g);
    // Stable paths inside guest
    binds.push({
      source: resolveEnginePath(g),
      target: i === 0 ? "/opt/contract/goss.yaml" : `/opt/contract/${name}`,
      mode: "ro",
    });
  });

  const builder = new RootlessPodmanContainer(opts.image)
    .withEntrypoint(["/bin/bash", "-c"])
    .withCommand(["sleep infinity"])
    .withWorkingDir("/work")
    .withEnvironment(env)
    .withBindMounts(binds)
    .withSecurityOpt("label=disable")
    .withWaitStrategy(Wait.forSuccessfulCommand("true"))
    .withStartupTimeout(opts.startupMs ?? 120_000)
    .withAutoRemove(true);

  const container = await builder.start();

  return {
    container,
    workDir,
    gossBin,
    gossList,
    aiRoot,
    async runGoss(gossGuestPath = "/opt/contract/goss.yaml") {
      const result = await container.exec([
        "/opt/contract/goss",
        "-g",
        gossGuestPath,
        "validate",
        "--format",
        "documentation",
      ]);
      return {
        exitCode: result.exitCode,
        stdout: result.output,
        stderr: "",
        pass: result.exitCode === 0,
      };
    },
    async exec(command) {
      const result = await container.exec(command);
      return { exitCode: result.exitCode, output: result.output };
    },
    async stop() {
      try {
        await container.stop();
      } catch {
        // already gone / ryuk raced
      }
    },
  };
}
