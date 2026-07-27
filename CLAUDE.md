# System Monitor: Claude Code context

Native macOS menu bar system monitor. Swift/SwiftUI + AppKit. Live CPU, GPU,
memory, disk and network, colour-coded in the menu bar with a panel one click
away. Public repo: `github.com/delarc0/system-monitor`.

## Ownership / identity

- Author: Erik `<erik@lab37.io>`
- Bundle ID: `se.lab37.systemmonitor.mac`
- Team ID: `4D2U237VRC` (LAB37 MEDIA AB)
- Target: macOS 14+, Apple Silicon and Intel

## Stack

- Swift 5.9, SwiftUI + AppKit, `LSUIElement=YES` menu bar app
- Swift Charts for the network graph. Everything else is hand-drawn `Path`.
- Sparkle 2.6 via SPM, wired but not finished (see Distribution)
- XcodeGen: `project.yml` is the source of truth. Both
  `SystemMonitor.xcodeproj/` and `SystemMonitor/Info.plist` are generated and
  gitignored. Never edit either; edit `project.yml` and run `xcodegen generate`.

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

`MetricsService` (main actor) runs one sampling loop, builds a `Snapshot` per
tick and publishes it. `MenuBarController` owns the `NSStatusItem` and the
`NSPopover`. Views are pure functions of `Snapshot`.

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

Then find the window and capture it:

```bash
# CGWindowListCopyWindowInfo for owner "System Monitor" gives the window id
screencapture -x -o -l <window-id> panel.png
```

Do this rather than trusting an offscreen `ImageRenderer`. `ImageRenderer` draws
AppKit controls (segmented pickers, sliders, toggles) as blank placeholders, and
it will happily render synthetic data that hides real bugs. Two defects in this
codebase were caught only by screenshotting the live app.

## Gotchas worth knowing

These were all real bugs. Do not reintroduce them.

- **Network counters must be 64-bit.** `getifaddrs` exposes `if_data`, whose
  `ifi_ibytes`/`ifi_obytes` are `u_int32_t` and wrap every 4 GiB. Widening a
  wrapped counter to `UInt64` before subtracting produces a ~1.8e19 delta that
  pins the chart scale. Use `sysctl(NET_RT_IFLIST2)` and `if_data64`.
- **Clamp counter deltas and guard time gaps.** Interfaces and disks come and go,
  and the machine sleeps. Both samplers, and `AlertMonitor`, discard samples
  spanning more than 15 seconds.
- **Never let the panel's hosting controller live when the popover is closed.**
  Retaining it makes SwiftUI re-evaluate the whole panel every tick for a hidden
  view. That alone cost 28% CPU. Build it on open, tear it down on close, and
  gate process sampling on visibility.
- **Swift Charts marks need an explicit `series:`.** Without it, marks sharing an
  x value are merged into one series and one style, so the second area silently
  takes the first one's colour.
- **`Path.addLines` starts with its own `move(to:)`.** Using it to build a filled
  area orphans the baseline corner and closes the shape diagonally, so flat data
  renders as a wedge. Use explicit `addLine(to:)`.
- **Do not pre-fill history arrays with zeros.** A zero is a real reading, and
  padding draws a fake flat line for the first minutes after launch. Series start
  empty and grow to `capacity`; views right-anchor a partial series.
- **`ps %cpu` is a decaying average**, not instantaneous. Accepted deliberately:
  `proc_pid_rusage` is instantaneous but returns EPERM for other users'
  processes, which would drop every root daemon from the list.
- **`ps` stderr must be `FileHandle.nullDevice`.** Nothing drains it, and a
  `Pipe` deadlocks the child once its buffer fills.

## Conventions

- No em dashes anywhere, including code comments.
- Comments explain why, not what. Most comments here record a bug that was
  actually hit; keep that bar.
- No `Co-Authored-By` trailers. Every commit is Erik's.

## Distribution

Release builds sign with the Developer ID under the hardened runtime and
notarize cleanly. `./scripts/release.sh --check` tells you if this Mac is
release-ready; `./scripts/release.sh 0.3.0` builds, notarizes, staples and stages
a zip without pushing anything.

Sparkle auto-update is deliberately unfinished: the EdDSA public key in
`project.yml` is a placeholder and no appcast is hosted, so
`SUEnableAutomaticChecks` is `NO`. Finishing it is only worth doing if the app
is ever handed to people who need updates. See `distribution/README.md`.
