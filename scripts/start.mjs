import { access } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFile } from "node:child_process";
import { promisify } from "node:util";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const root = resolve(__dirname, "..");
const appName = "CrabSwitcher";
const appBundle = join(root, "dist", `${appName}.app`);

const execFileAsync = promisify(execFile);

function runNode(scriptPath) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [scriptPath], {
      cwd: root,
      stdio: "inherit",
      env: process.env
    });
    child.on("exit", (code) => {
      if (code === 0) {
        resolvePromise();
      } else {
        reject(new Error(`script exited with code ${code}`));
      }
    });
    child.on("error", reject);
  });
}

function runCommand(command, args) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, {
      cwd: root,
      stdio: "inherit",
      env: process.env
    });
    child.on("exit", (code) => {
      if (code === 0) {
        resolvePromise();
      } else {
        reject(new Error(`${command} ${args.join(" ")} exited with code ${code}`));
      }
    });
    child.on("error", reject);
  });
}

async function main() {
  console.log("\n=== CrabSwitcher: start ===\n");

  console.log("1) Building…");
  await runNode(join(root, "scripts", "build.mjs"));

  console.log("\n2) Stopping any running instance…");
  try {
    await execFileAsync("pkill", [
      "-f",
      "CrabSwitcher.app/Contents/MacOS/CrabSwitcher"
    ]);
  } catch {
    // pkill returns 1 if no process matched; ignore
  }

  try {
    await access(appBundle);
  } catch {
    throw new Error(`App bundle not found: ${appBundle}`);
  }

  console.log("3) Launching app…\n   → " + appBundle);
  await runCommand("open", [appBundle]);

  console.log("\n---\n");
  console.log("If Input Monitoring is missing (menu shows red) after a rebuild, remove the app");
  console.log("from System Settings → Privacy & Security → Input Monitoring, then relaunch and allow it again.\n");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
