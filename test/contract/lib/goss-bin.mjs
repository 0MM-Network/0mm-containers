/**
 * Ensure a pinned Goss binary lives under AI_ROOT/cache/goss (not on the host PATH).
 */
import fs from "node:fs";
import path from "node:path";
import https from "node:https";
import { execFileSync } from "node:child_process";

/** Pin bumps should be noted in ADR 0001 decision log. */
export const GOSS_VERSION = "0.4.9";

const GOSS_URL =
  `https://github.com/goss-org/goss/releases/download/v${GOSS_VERSION}/goss-linux-amd64`;

export function defaultAiRoot() {
  return process.env.AI_ROOT || path.join(process.env.HOME || "", "src/ai");
}

export function gossCachePath(aiRoot = defaultAiRoot()) {
  return path.join(aiRoot, "cache", "goss", "goss");
}

function download(url, dest) {
  return new Promise((resolve, reject) => {
    const follow = (u, redirectsLeft) => {
      https
        .get(u, (res) => {
          if (
            res.statusCode >= 300 &&
            res.statusCode < 400 &&
            res.headers.location &&
            redirectsLeft > 0
          ) {
            res.resume();
            follow(res.headers.location, redirectsLeft - 1);
            return;
          }
          if (res.statusCode !== 200) {
            reject(new Error(`download ${u} → HTTP ${res.statusCode}`));
            res.resume();
            return;
          }
          const tmp = `${dest}.partial`;
          const out = fs.createWriteStream(tmp, { mode: 0o755 });
          res.pipe(out);
          out.on("finish", () => {
            out.close(() => {
              fs.renameSync(tmp, dest);
              fs.chmodSync(dest, 0o755);
              resolve(dest);
            });
          });
          out.on("error", reject);
        })
        .on("error", reject);
    };
    follow(url, 5);
  });
}

/**
 * @returns {Promise<string>} absolute path to goss binary
 */
export async function ensureGossBinary(aiRoot = defaultAiRoot()) {
  const dest = gossCachePath(aiRoot);
  fs.mkdirSync(path.dirname(dest), { recursive: true });

  if (fs.existsSync(dest)) {
    try {
      const ver = execFileSync(dest, ["--version"], { encoding: "utf8" }).trim();
      if (ver.includes(GOSS_VERSION)) {
        return dest;
      }
    } catch {
      // re-download
    }
  }

  process.stderr.write(`Fetching goss v${GOSS_VERSION} → ${dest}\n`);
  await download(GOSS_URL, dest);
  return dest;
}
