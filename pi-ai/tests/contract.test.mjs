/**
 * Layer B contract tests for pi-ai (Testcontainers + Goss).
 * ADR: 0mm-containers/docs/adr/0001-container-contract-testing.md
 *
 * XAI coverage:
 * - Base goss.yaml must PASS without any provider key (image is not key-coupled).
 * - goss-provider-env.yaml must PASS when orchestrator injects XAI_API_KEY
 *   (guest contract for shim --secret / -e injection).
 * - goss-provider-env.yaml must FAIL when the key is absent.
 * Real credentials and provider HTTP are out of scope (layer A owns secret UX).
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { startContractContainer } from "../../test/contract/lib/harness.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PKG = path.resolve(__dirname, "..");
const IMAGE = process.env.PI_IMAGE || "localhost/pi:latest";
const GOSS = path.join(PKG, "goss.yaml");
const GOSS_ENV = path.join(PKG, "goss-provider-env.yaml");
const SUITE_XAI = "contract-test-xai-key";

/** Prefer host-visible tree (/work or AI_ROOT) so nested Testcontainers binds resolve. */
function makeWorkDir(prefix) {
  const aiRoot = process.env.AI_ROOT || "";
  const bases = [
    aiRoot && path.join(aiRoot, "cache"),
    "/work/cache",
    os.tmpdir(),
  ].filter(Boolean);
  for (const base of bases) {
    try {
      fs.mkdirSync(base, { recursive: true });
      return fs.mkdtempSync(path.join(base, prefix));
    } catch {
      // try next
    }
  }
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

describe("pi-ai container contract (with XAI_API_KEY)", () => {
  /** @type {Awaited<ReturnType<typeof startContractContainer>>} */
  let suite;
  let workDir;

  before(async () => {
    workDir = makeWorkDir("pi-contract-");
    fs.writeFileSync(path.join(workDir, ".contract-marker"), "pi-contract\n", "utf8");

    suite = await startContractContainer({
      image: IMAGE,
      workDir,
      gossFiles: [GOSS, GOSS_ENV],
      env: {
        XAI_API_KEY: SUITE_XAI,
      },
    });
  });

  after(async () => {
    if (suite) await suite.stop();
    if (workDir && fs.existsSync(workDir)) {
      fs.rmSync(workDir, { recursive: true, force: true });
    }
  });

  it("satisfies base goss contract (mounts, binaries, HOME, cwd)", async () => {
    const result = await suite.runGoss("/opt/contract/goss.yaml");
    assert.equal(result.exitCode, 0, `goss failed:\n${result.stdout}`);
  });

  it("goss sees orchestrator-injected XAI_API_KEY (secret→env guest surface)", async () => {
    const result = await suite.runGoss("/opt/contract/goss-provider-env.yaml");
    assert.equal(
      result.exitCode,
      0,
      `provider env goss failed:\n${result.stdout}`,
    );
  });

  it("exposes host-seeded work file via /work", async () => {
    const r = await suite.exec([
      "bash",
      "-c",
      "test -f /work/.contract-marker && cat /work/.contract-marker",
    ]);
    assert.equal(r.exitCode, 0, r.output);
    assert.match(r.output, /pi-contract/);
  });
});

describe("pi-ai container contract (without XAI_API_KEY)", () => {
  /** @type {Awaited<ReturnType<typeof startContractContainer>>} */
  let suite;
  let workDir;

  before(async () => {
    workDir = makeWorkDir("pi-contract-nokey-");
    fs.writeFileSync(path.join(workDir, ".contract-marker"), "pi-contract\n", "utf8");

    suite = await startContractContainer({
      image: IMAGE,
      workDir,
      gossFiles: [GOSS, GOSS_ENV],
      // no XAI_API_KEY
    });
  });

  after(async () => {
    if (suite) await suite.stop();
    if (workDir && fs.existsSync(workDir)) {
      fs.rmSync(workDir, { recursive: true, force: true });
    }
  });

  it("base goss still passes without provider keys", async () => {
    const result = await suite.runGoss("/opt/contract/goss.yaml");
    assert.equal(result.exitCode, 0, `goss failed:\n${result.stdout}`);
  });

  it("provider-env goss fails when XAI_API_KEY is absent", async () => {
    const result = await suite.runGoss("/opt/contract/goss-provider-env.yaml");
    assert.notEqual(
      result.exitCode,
      0,
      "expected provider goss to fail without XAI_API_KEY",
    );
  });
});
