import { mkdir, rm, cp, access, mkdtemp } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { tmpdir } from "node:os";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const root = resolve(__dirname, "..");
const distRoot = join(root, "dist");
const appName = "CrabSwitcher";
const appBundle = join(distRoot, `${appName}.app`);
const dmgPath = join(distRoot, `${appName}.dmg`);

function run(command, args, options = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, {
      cwd: root,
      stdio: "inherit",
      ...options
    });
    child.on("exit", (code) => {
      if (code === 0) {
        resolvePromise();
        return;
      }
      reject(new Error(`${command} ${args.join(" ")} failed with code ${code}`));
    });
    child.on("error", reject);
  });
}

async function ensureBuild() {
  try {
    await access(appBundle);
  } catch {
    console.log("App bundle is missing, running build first...");
    await run("node", ["./scripts/build.mjs"]);
  }
}

await mkdir(distRoot, { recursive: true });
await ensureBuild();

const stagingDir = await mkdtemp(join(tmpdir(), "crabswitcher-dmg-"));
try {
  await cp(appBundle, join(stagingDir, `${appName}.app`), { recursive: true });
  await rm(dmgPath, { force: true });

  console.log("Creating DMG...");
  await run("hdiutil", [
    "create",
    "-volname",
    appName,
    "-srcfolder",
    stagingDir,
    "-ov",
    "-format",
    "UDZO",
    dmgPath
  ]);

  console.log(`Done. DMG: ${dmgPath}`);
} finally {
  await rm(stagingDir, { recursive: true, force: true });
}
