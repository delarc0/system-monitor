# AGENTS.md: installing System Monitor

Instructions for a coding agent (Claude Code, etc.) asked to install System
Monitor on this Mac. Follow them top to bottom. System Monitor is a native macOS
menu bar app showing live CPU, GPU, memory, disk and network usage. Everything
runs on-device: no account, no network, no permissions to grant.

## TL;DR

```bash
./install.sh
```

That checks prerequisites, generates the Xcode project, builds, installs to
`/Applications` and launches it. Unlike most menu bar utilities there is nothing
for the human to approve afterwards, so you can complete this unattended.

## Requirements (install.sh checks all of these and stops with a clear message)

- macOS 14 (Sonoma) or later. Apple Silicon or Intel; Intel loses only the
  P/E core split line.
- Full **Xcode**, not just Command Line Tools. If missing, the human installs it
  from the App Store and then runs
  `sudo xcode-select -s /Applications/Xcode.app`. You cannot install Xcode
  for them.
- **xcodegen**. If Homebrew is present install.sh runs `brew install xcodegen`
  itself. If Homebrew is missing, tell the human to install it from
  https://brew.sh first.

No Apple Developer account is needed to install. It only matters for
distributing the app to other machines.

## Step by step

1. **Run the installer.**
   ```bash
   ./install.sh
   ```
   The first build fetches Sparkle via SPM and takes a minute or two. On failure
   the full log is at `/tmp/system-monitor-build.log`; the script prints the last
   25 lines for you.

2. **Confirm it is running.**
   ```bash
   pgrep -fl "System Monitor.app/Contents/MacOS"
   ```
   The menu bar shows a coloured CPU percentage. There is no Dock icon and no
   main window: it is an `LSUIElement` app.

3. **Tell the human what they got.** Click the menu bar reading for the panel.
   The gear in the panel opens Settings. If they want it to survive a reboot they
   must turn on **Launch at login** in Settings, which you cannot do for them
   because it is a `SMAppService` registration owned by the app.

## Which build you get

install.sh picks automatically:

- **Developer ID certificate present** (team `4D2U237VRC`): builds Release,
  signed with the hardened runtime.
- **No certificate**: builds Debug with ad-hoc signing.

Either way the installed app lives at `/Applications/System Monitor.app`, and
either way it is a **local build, not a notarized one**. It runs here because an
app you built yourself carries no quarantine attribute, so Gatekeeper never
assesses it. `spctl` will still say `rejected`; that is expected and does not
stop it launching.

Producing something you can hand to another Mac is a different job:
`./scripts/release.sh <version>` archives, notarizes with Apple, staples the
ticket and stages a zip.

## Do not

- **Do not edit `SystemMonitor/Info.plist`.** XcodeGen generates it from
  `project.yml`, so your changes are erased on the next build. It is gitignored
  for that reason. Edit `project.yml`.
- **Do not commit `SystemMonitor.xcodeproj/`.** Also generated, also gitignored.
- **Do not run the app out of `build/`.** That is a build artifact and it breaks
  when the directory is cleaned. Install to `/Applications` via install.sh.

## Uninstalling

```bash
pkill -f "System Monitor.app/Contents/MacOS"
rm -rf "/Applications/System Monitor.app"
defaults delete se.lab37.systemmonitor.mac 2>/dev/null || true
```

The `defaults delete` clears saved preferences (update interval, menu bar mode,
alert thresholds). Skip it if the human is reinstalling and wants them kept.

## Troubleshooting

**Build fails with a signing error.** Pass ad-hoc signing explicitly:
```bash
xcodebuild -project SystemMonitor.xcodeproj -scheme SystemMonitor \
  -configuration Debug -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic build
```

**Nothing appears in the menu bar.** The bar is probably full. macOS silently
drops status items when there is no room; quit something else or widen the bar.
Check the process is alive with `pgrep` first.

**GPU row is missing.** `GPUSampler` reads `AGXAccelerator` via IOKit, which
does not exist on Intel Macs with discrete GPUs. The row hides itself rather
than showing a wrong number. This is expected, not a bug.

For project context and architecture see [CLAUDE.md](CLAUDE.md); for the release
pipeline see [distribution/README.md](distribution/README.md).
