# System Monitor

**Lightweight macOS menu bar system monitor by LAB37.**

Native Swift/SwiftUI menu bar app. Live CPU, GPU, memory, disk and network, plus how far along your weekly Claude Code allowance is. No Dock icon, no account, no permissions to grant.

## What it shows

- **Menu bar**: labeled readings with the number color-coded, Claude first, plus a hover tooltip that adds the disk and the reset time. Memory is colored by the kernel's pressure state, not its percentage. A red disk figure appears under 10% free
- **CPU, GPU, Memory**: a 0 to 100% trace of the last 2 minutes. Memory matches Activity Monitor's "Memory Used"
- **Disk**: capacity used, matching Finder's accounting, plus read and write rates when there is real I/O
- **Network**: download above the axis and upload mirrored below, on one scale
- **Top processes**: top CPU and top memory, each process resolved to its owning app, so all of an app's helpers read as one row. Click for Activity Monitor, right-click to reveal
- **Claude**: percent of the weekly allowance used, how much of the week has gone, and when it resets. The row is hidden if Claude Code isn't installed

The readings are local. Only `claude` and Sparkle's update check use the network, and the update check stays off until the first signed release.

## Requirements

macOS 14 or later, on Apple Silicon or Intel. Intel Macs with a discrete GPU have no GPU row.

## Install

```bash
./install.sh
```

Builds, installs to `/Applications` and launches. See [AGENTS.md](AGENTS.md).

## Claude usage

Claude Code saves its last usage reading in `~/.claude.json`, and a running Claude Code process rewrites it about every 5 minutes. The app reads that file every 30 seconds, which costs almost nothing and needs no credentials.

When that reading is over 15 minutes old, the app runs `claude -p /usage` at background priority, at most every 30 minutes, or every 5 if the panel is open. That costs no usage but is heavy: 8 to 24 seconds and about 500 MB.

Neither source is documented. If both change, the row says "no data" rather than a wrong number.

## Development

See [CLAUDE.md](CLAUDE.md) for architecture and known gotchas, and [distribution/README.md](distribution/README.md) for releases.

---

**LAB37**
