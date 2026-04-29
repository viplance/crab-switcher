import { mkdir, rm, cp, access, chmod } from "node:fs/promises";
import { dirname, join, resolve, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execSync } from "node:child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const root = resolve(__dirname, "..");
const distRoot = join(root, "dist");
const appName = "CrabSwitcher";
const appBundle = join(distRoot, `${appName}.app`);
const dmgPath = join(distRoot, `${appName}.dmg`);
const tempDmgPath = join(distRoot, "temp.dmg");
const backgroundPath = join(root, "assets", "dmg-background.png");

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

async function createDmg() {
  await mkdir(distRoot, { recursive: true });
  await ensureBuild();

  console.log("Preparing staging area...");
  await rm(dmgPath, { force: true });
  await rm(tempDmgPath, { force: true });

  // 1. Create a writable DMG
  console.log("Creating writable DMG...");
  await run("hdiutil", [
    "create",
    "-size", "100m",
    "-fs", "HFS+",
    "-volname", appName,
    "-ov",
    tempDmgPath
  ]);

  // 2. Mount it
  console.log("Mounting DMG...");
  const mountOutput = execSync(`hdiutil attach -readwrite "${tempDmgPath}"`).toString();
  const mountPointMatch = mountOutput.match(/\/Volumes\/(.*)/);
  if (!mountPointMatch) throw new Error("Failed to find mount point");
  const mountPoint = mountPointMatch[0].trim();

  try {
    console.log(`Mounted at: ${mountPoint}`);

    // 3. Copy files
    console.log("Copying files to DMG...");
    await cp(appBundle, join(mountPoint, `${appName}.app`), { recursive: true });
    
    console.log("Creating Applications symlink...");
    execSync(`ln -s /Applications "${join(mountPoint, "Applications")}"`);

    // 4. Set background
    const bgDestDir = join(mountPoint, ".background");
    await mkdir(bgDestDir, { recursive: true });
    await cp(backgroundPath, join(bgDestDir, "background.png"));

    // 5. Run AppleScript to style the window
    console.log("Applying styles via AppleScript...");
    const appleScript = `
      tell application "Finder"
        tell disk "${appName}"
          open
          delay 2
          set the container_window to container window
          set current view of container_window to icon view
          set toolbar visible of container_window to false
          set statusbar visible of container_window to false
          set the bounds of container_window to {400, 100, 1000, 500}
          set viewOptions to the icon view options of container_window
          set icon size of viewOptions to 128
          set arrangement of viewOptions to not arranged
          try
            set background picture of viewOptions to file ".background:background.png"
          on error err
            log "Background error: " & err
          end try
          set position of item "${appName}.app" to {150, 200}
          set position of item "Applications" to {450, 200}
          update without registering applications
          delay 2
          close
        end tell
      end tell
    `;
    
    try {
      await run("osascript", ["-e", appleScript]);
    } catch (e) {
      console.warn("Warning: AppleScript styling failed. The DMG will still work but might not look as pretty.");
    }

    // Give it a moment to sync
    await new Promise(r => setTimeout(r, 2000));

  } finally {
    console.log("Unmounting DMG...");
    execSync(`hdiutil detach "${mountPoint}"`);
  }

  // 6. Convert to compressed UDZO
  console.log("Converting to compressed DMG...");
  await run("hdiutil", [
    "convert", tempDmgPath,
    "-format", "UDZO",
    "-o", dmgPath
  ]);

  await rm(tempDmgPath, { force: true });
  console.log(`\nDone. Correct Installer: ${dmgPath}`);
}

createDmg().catch(err => {
  console.error("Failed to create DMG:", err);
  process.exit(1);
});
