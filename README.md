# CrabSwitcher

Simple macOS toolbar app that toggles keyboard language between English and Russian using the `Fn` key.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools (`swift`, `codesign`, `hdiutil`)
- Node.js + `pnpm`

## Build

```bash
pnpm build
```

Output:

- App bundle: `dist/CrabSwitcher.app`

## Run (build + launch)

```bash
pnpm start
```

This runs, in order:

1. `pnpm build` (Swift release + `.app` in `dist/`)
2. Stops any already-running `CrabSwitcher`
3. Opens `dist/CrabSwitcher.app`

## Create DMG installer

```bash
pnpm dmg
```

Output:

- Installer: `dist/CrabSwitcher.dmg`

## Folder layout

| Folder    | Purpose                                                               |
| --------- | --------------------------------------------------------------------- |
| `dist/`   | **Final shippable output.** This is the only folder you care about.   |
| `.build/` | Swift Package Manager intermediates (object files, cached artifacts). |

There is no separate `build/` folder anymore — `pnpm build` writes the `.app`
directly into `dist/`, and `pnpm dmg` uses an OS temp directory for staging.

## Notes for first launch

- The app runs in the macOS menu bar (`LSUIElement`).
- To receive global `Fn` key events, allow the app in:
  - `System Settings` → `Privacy & Security` → `Input Monitoring`
- The menu shows `🟢 Fn key monitoring active` once permission is detected.
  The app retries automatically every 2 seconds, so you don't need to relaunch
  after granting permission.
- If your preferred English or Russian layout has a custom name, ensure those
  layouts are added in macOS keyboard settings.

## Troubleshooting: "Input Monitoring permission needed" after rebuild

The app is ad-hoc signed, so every `pnpm build` produces a binary with a new
hash. macOS silently invalidates the previous permission grant, even though the
toggle in `System Settings` may still appear enabled. If the menu keeps showing
the red status after rebuilding:

1. Open `System Settings` → `Privacy & Security` → `Input Monitoring`
2. Select the existing `CrabSwitcher` entry and click `−` to remove it
3. Quit the app and relaunch `dist/CrabSwitcher.app`
4. macOS will re-prompt; allow it. The icon turns green within ~2 seconds.

## Troubleshooting: Fn key does nothing

On Apple Silicon and most modern Macs the Fn key is also the 🌐 (Globe) key.
The system intercepts it for built-in actions like opening Emoji & Symbols.
The app installs an HID-level event tap that catches the keystroke before
the system processes it, but if it still does nothing:

1. Open `System Settings` → `Keyboard` → `Press 🌐 key to:` and set it to
   `Do Nothing`. (`Change Input Source` already toggles natively, in which
   case CrabSwitcher is redundant.)
2. Check the menu-bar item: it should show `🟢 Fn key monitoring active` when
   Input Monitoring is in effect. If it stays red, see the “permission needed
   after rebuild” section above.
