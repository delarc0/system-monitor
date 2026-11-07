# System Monitor: Claude Code context

Native macOS menu bar system monitor. Swift/SwiftUI + AppKit. Live CPU, GPU,
memory, disk and network, colour-coded in the menu bar with a panel one click
away, plus the weekly Claude Code allowance. Public repo: `github.com/delarc0/system-monitor`.

## Ownership / identity

- Author: Erik `<erik@lab37.io>`
- Bundle ID: `se.lab37.systemmonitor.mac`
- Team ID: `4D2U237VRC` (LAB37 MEDIA AB)
- Target: macOS 14+, Apple Silicon and Intel

## Stack

- Swift 6 language mode (Xcode 27), SwiftUI + AppKit, `LSUIElement=YES` menu bar app
- All graphs are hand-drawn `Path`. Sparkle 2.10 via SPM is the one dependency.
- XcodeGen: `project.yml` is the source of truth. Both
  `SystemMonitor.xcodeproj/` and `SystemMonitor/Info.plist` are generated and
  gitignored. Never edit either; edit `project.yml` and run `xcodegen generate`.

## Tests

```bash
xcodebuild -project SystemMonitor.xcodeproj -scheme SystemMonitor \
  -derivedDataPath build test CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic
```

`SystemMonitorTests` hosts in the app. XcodeGen derives the host path from the
target name, so `TEST_HOST` and `PRODUCT_MODULE_NAME` are set by hand in
`project.yml` (the product name has a space). The `linkd.autoShortcut` noise in
the test log is the host being a menu bar app, not a failure.

## Build / run

```bash
./install.sh          # builds, installs to /Applications, launches
```

Manual:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project SystemMonitor.xcodeproj -scheme SystemMonitor \
  -configuration Debug -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic build
open "build/Build/Products/Debug/System Monitor.app"
```

The target and scheme are `SystemMonitor`; the built bundle is
`System Monitor.app`, with a space, so Finder agrees with `CFBundleDisplayName`.

`AGENTS.md` is the install guide to hand to an agent; `README.md` is the human
intro.

## Architecture

`MetricsService` (main actor) runs three loops: the main tick builds a `Snapshot`
from microsecond reads, `ps` runs only while the panel is open, and `claude` runs
rarely in the background. Slow work can never hold up the menu bar. Views are pure
functions of what it publishes.

`ClaudeSampler` reads `claude -p /usage`, not the status line JSON, which only moves
in an interactive CLI session and read a stale 0% on a Mac driven through the Agent
SDK. Do not use the undocumented OAuth usage endpoint community tools hit.

`MenuBarController` exists because SwiftUI's `MenuBarExtra` flattens per-segment
colours to the menu bar's template tint. The title is built as an
`NSAttributedString` with explicit `NSColor` instead.

Samplers live in `Metrics/`, one per resource, each returning a value type.
`ProcessSampler` is an `actor` because it owns a cache and blocks on `ps`.

## Testing UI changes

The panel is a menu bar popover, which cannot be opened from a script. There is
a DEBUG-only hook for exactly this:

```bash
open -n --env SYSMON_OPEN_PANEL=120 "build/Build/Products/Debug/System Monitor.app"
# value is a delay in seconds, so graphs can fill before you screenshot
```

Add `--env SYSMON_PANEL_PNG=/path/panel.png` to have it write the panel to a PNG
3 seconds after opening, plus the menu bar title as `panel-menubar.png`, no Screen
Recording permission needed. The PNGs have no background, so composite them before
judging contrast. Add `--env SYSMON_LIGHT=1` for the panel in the light theme.

Do this rather than trusting an offscreen `ImageRenderer`. `ImageRenderer` draws
AppKit controls (segmented pickers, sliders, toggles) as blank placeholders, and
it will happily render synthetic data that hides real bugs. Two defects in this
codebase were caught only by looking at the live app.

## Gotchas worth knowing

These were all real bugs. Do not reintroduce them.

- **Network counters must be 64-bit.** `getifaddrs` exposes `if_data`, whose
  `ifi_ibytes`/`ifi_obytes` are `u_int32_t` and wrap every 4 GiB. Widening a
  wrapped counter to `UInt64` before subtracting produces a ~1.8e19 delta that
  pins the chart scale. Use `sysctl(NET_RT_IFLIST2)` and `if_data64`.
- **Rates are per key, never from a sum.** Interfaces and disks come and go, and
  one returning with its old byte count read as a huge burst when summed.
  `RateCounter` baselines new keys and discards gaps over 15 seconds (sleep).
- **Keep the App Nap activity.** A napped timer overruns that 15-second guard, and
  every rate then reads as a sleep.
- **Memory is internal - purgeable + wired + compressed.** `active` includes file
  cache and read 8 points high on a 64 GB Mac.
- **Never let the panel's hosting controller live when the popover is closed.**
  Retaining it makes SwiftUI re-evaluate the whole panel every tick for a hidden
  view. That alone cost 28% CPU. Build it on open, tear it down on close, and
  gate process sampling on visibility.
- **`Path.addLines` starts with its own `move(to:)`.** Using it to build a filled
  area orphans the baseline corner and closes the shape diagonally, so flat data
  renders as a wedge. Use explicit `addLine(to:)`.
- **Do not pre-fill history arrays with zeros.** A zero is a real reading, and
  padding draws a fake flat line for the first minutes after launch. Series start
  empty and grow to `capacity`; views right-anchor a partial series.
- **`ps %cpu` is a decaying average**, not instantaneous. Accepted deliberately:
  `proc_pid_rusage` is instantaneous but returns EPERM for other users'
  processes, which would drop every root daemon from the list.
- **`ps` needs `LC_ALL=C`.** Under a Swedish locale it prints `145,6`, which no
  number parser accepts, and every row disappears.
- **`runProcess` writes to a temp file, never a Pipe.** A Pipe deadlocks a child
  that fills it, and reading one to EOF hangs while a grandchild holds it open.
- **Claude's parse miss is "no data", never 0%.** A zero reads as a full allowance.
- **The first tick publishes nothing.** CPU is a delta with no baseline yet;
  `buildSnapshot` returns nil rather than a 0% that the history would keep.

## Conventions

- No em dashes anywhere, including code comments.
- Comments explain why, not what. Most comments here record a bug that was
  actually hit; keep that bar.
- No `Co-Authored-By` trailers. Every commit is Erik's.

## Distribution

`./scripts/release.sh --check` says whether this Mac is release-ready.
`./scripts/release.sh 0.5.0` builds, notarizes and staples, signs for Sparkle and
stages the appcast; `--publish` also pushes it. See `distribution/README.md`.
