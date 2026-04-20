# System Monitor

**Lightweight macOS menu bar system monitor by LAB37.**

Native Swift/SwiftUI menu bar app. Live CPU, GPU, memory, and network stats — color-coded in your menu bar, full detail one click away. No bloat, no Dock icon, no cloud.

## Features

- **Menu bar pill** — CPU % and memory % side-by-side, per-segment color-coded (green → orange → red via smooth hue interpolation)
- **Animated gauges** — CPU, GPU, Memory with spring-animated fills
- **Network graph** — Swift Charts area chart with gradient fills for download (blue) and upload (orange)
- **Top processes** — segmented Top CPU / Top Memory, memory aggregated by app name so Chrome-style multi-process apps show real totals
- **P/E core split** — average load per core cluster shown under the CPU bar on Apple Silicon
- **Preferences** — update interval (1/2/5 s), menu bar display mode (CPU / CPU+MEM / CPU+GPU / All), launch at login
- **Zero permissions** — no sudo, no accessibility, no microphone. Pure IOKit + Mach APIs.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1–M5) — Intel works minus the P/E core split

## Build & run locally

```bash
brew install xcodegen
xcodegen generate
open SystemMonitor.xcodeproj
# ⌘R in Xcode, or:
xcodebuild -project SystemMonitor.xcodeproj -scheme SystemMonitor \
  -configuration Debug -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic build
open build/Build/Products/Debug/SystemMonitor.app
```

The `Xcode.xcodeproj` is regenerated from `project.yml` — don't commit it (it's in `.gitignore`).

## Architecture

```
SystemMonitor/
  SystemMonitorApp.swift       @main — MenuBarExtra scene + Settings scene
  AppPreferences.swift         UserDefaults-backed preferences + SMAppService
  UpdaterController.swift      Sparkle wrapper
  Metrics/
    Snapshot.swift             Data types
    Sysctl.swift               Typed sysctlbyname wrappers
    CPUSampler.swift           host_statistics / host_processor_info
    MemorySampler.swift        host_statistics64(HOST_VM_INFO64)
    GPUSampler.swift           IOKit / AGXAccelerator
    NetworkSampler.swift       getifaddrs + if_data
    ProcessSampler.swift       /bin/ps → aggregated by name
    MetricsService.swift       Actor-ish orchestrator, publishes Snapshot
  Views/
    LoadColor.swift            Green→red HSL interpolation helper
    MenuBarLabel.swift         Color-coded status item content
    PanelView.swift            Root panel composition
    GaugeRow.swift             Icon + label + animated capsule + %
    NetworkChartView.swift     Swift Charts area chart
    ProcessListView.swift      Segmented Top CPU / Top Memory
    SettingsView.swift         Preferences + About tabs
```

## Distribution

Sparkle auto-update is wired (`project.yml` has Sparkle SPM, Info.plist has `SUFeedURL` + `SUPublicEDKey` placeholder). Before the first signed release, mint an EdDSA keypair and paste the public key into `project.yml`. See [distribution/README.md](distribution/README.md) for the release recipe (mirrors Bark-mac).

Updates are blocked on Apple Developer ID approval — Sparkle refuses to apply updates that aren't both EdDSA-signed and codesigned by a trusted identity.

---

**LAB37**
