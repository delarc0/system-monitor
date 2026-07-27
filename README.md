# System Monitor

**Lightweight macOS menu bar system monitor by LAB37.**

Native Swift/SwiftUI menu bar app. Live CPU, GPU, memory, and network stats, color-coded in your menu bar, with full detail one click away. No bloat, no Dock icon, no cloud.

## Features

- **Menu bar pill**: the readings themselves are color-coded (green → orange → red via smooth hue interpolation); no icons or bullets eating menu bar width, with a hover tooltip naming each figure
- **Sparkline gauges**: CPU, GPU, Memory and Disk, each a fixed 0–100 % trace so the height still reads as the current level while showing the last 60 samples
- **Disk**: capacity used (matching Finder's "important usage" accounting) plus live read/write throughput from IOKit
- **Network graph**: Swift Charts area chart, download (blue) above the axis and upload (orange) mirrored below. 64-bit interface counters, so a 4 GiB wrap can't spike the graph. Scale is either shared (comparable) or per-direction (detailed)
- **Top processes**: segmented Top CPU / Top Memory, with each process resolved to its owning app bundle (icon, real name) and aggregated by it, so Chrome's 38 helpers read as one "Google Chrome" row with the real total. Click for Activity Monitor, right-click to reveal
- **Sustained-load alerts**: per-metric thresholds that only fire once a metric has stayed over the line for a chosen window, with hysteresis so a value sitting on the threshold doesn't flap. Optional notification, off by default
- **P/E core split**: average load per core cluster shown under the CPU bar on Apple Silicon
- **Preferences**: update interval (1/2/5 s), menu bar display mode, network graph scale, alert thresholds, launch at login
- **Idle-cheap**: the panel's SwiftUI hierarchy is built on open and torn down on close, and the process sampler only runs while the panel is visible. Sitting in the menu bar costs ~0% CPU
- **Zero permissions**: no sudo, no accessibility, no microphone. Pure IOKit + Mach APIs.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1–M5). Intel works minus the P/E core split

## Build & run locally

```bash
brew install xcodegen
xcodegen generate
open SystemMonitor.xcodeproj
# ⌘R in Xcode, or:
xcodebuild -project SystemMonitor.xcodeproj -scheme SystemMonitor \
  -configuration Debug -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic build
open "build/Build/Products/Debug/System Monitor.app"
```

The target and scheme are `SystemMonitor`; the built bundle is `System Monitor.app`
(`PRODUCT_NAME` carries the space so Finder, the Dock and Spotlight agree with
`CFBundleDisplayName`).

The `SystemMonitor.xcodeproj` is regenerated from `project.yml`, so don't commit it (it's in `.gitignore`).

## Architecture

```
SystemMonitor/
  SystemMonitorApp.swift       @main, AppDelegate + Settings scene
  MenuBarController.swift      NSStatusItem + NSPopover, attributed menu bar title
  AppPreferences.swift         UserDefaults-backed preferences + SMAppService
  UpdaterController.swift      Sparkle wrapper
  Metrics/
    Snapshot.swift             Data types
    Sysctl.swift               Typed sysctlbyname wrappers
    CPUSampler.swift           host_statistics / host_processor_info
    MemorySampler.swift        host_statistics64(HOST_VM_INFO64)
    GPUSampler.swift           IOKit / AGXAccelerator
    DiskSampler.swift          Volume capacity + IOBlockStorageDriver bytes
    NetworkSampler.swift       sysctl(NET_RT_IFLIST2) → if_data64
    ProcessSampler.swift       actor; /bin/ps → resolved to app bundles
    AlertMonitor.swift         Sustained-breach detection + hysteresis
    AlertNotifier.swift        Opt-in UserNotifications wrapper
    MetricsService.swift       Main-actor orchestrator, publishes Snapshot
  Views/
    LoadColor.swift            Green→red HSL interpolation helper
    PanelView.swift            Root panel composition + alert banner
    GaugeRow.swift             Icon + label + fixed-scale sparkline + %
    NetworkChartView.swift     Mirrored download/upload chart
    ProcessListView.swift      Segmented Top CPU / Top Memory
    SettingsView.swift         General + Alerts + About tabs
  Assets.xcassets/             AppIcon
```

`MenuBarController` owns the status item because SwiftUI's `MenuBarExtra`
flattens per-segment colors to the menu bar's template tint; the title is built
as an `NSAttributedString` instead.

## Distribution

Sparkle auto-update is wired: `project.yml` carries the Sparkle SPM dependency plus `SUFeedURL`, `SUPublicEDKey` and `SUEnableAutomaticChecks`, and generates `Info.plist` from them. See [distribution/README.md](distribution/README.md) for the release recipe (mirrors Bark-mac).

Release builds sign with `Developer ID Application: LAB37 MEDIA AB (4D2U237VRC)` under the hardened runtime, verified end to end. Two things remain before a first release: the EdDSA keypair is still a placeholder, and the appcast isn't hosted. Until both are done `SUEnableAutomaticChecks` stays `NO`, so the app neither prompts to auto-update nor fetches a feed that doesn't exist yet.

---

**LAB37**
