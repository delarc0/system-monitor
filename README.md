# System Monitor

**Lightweight macOS menu bar system monitor by LAB37.**

Live CPU, GPU, memory, and network stats in your menu bar. Click to see a detailed panel with a real-time network throughput graph. No bloat, no Dock icon, no cloud.

## Features

- **Menu bar CPU %** - Color-coded (green/orange/red) always visible in your menu bar
- **GPU utilization** - Apple Silicon GPU usage via ioreg (no sudo required)
- **Memory usage** - RAM used/total with swap info
- **Network graph** - Live download/upload throughput with 60-second area chart
- **Top processes** - 5 most CPU-hungry processes at a glance
- **Dark panel** - Clean, high-contrast dropdown with white-on-dark design
- **Zero permissions** - No sudo, no accessibility, no microphone. Just run it.

---

## Requirements

- macOS 13+ (Ventura or later)
- Apple Silicon (M1/M2/M3/M4)
- Python 3.9+

## Install

```bash
git clone https://github.com/delarc0/system-monitor.git
cd system-monitor
chmod +x run.sh
./run.sh
```

The run script creates a virtual environment, installs dependencies, and launches the app. First launch takes a few seconds for setup.

## Usage

1. A CPU percentage appears in your menu bar (e.g. `47%`)
2. **Click it** and select **Show Details** to open the stats panel
3. The panel shows CPU, GPU, memory bars and a live network graph
4. Stats update every 2 seconds
5. **Quit** from the menu bar dropdown

## Dependencies

- `psutil` - CPU, memory, network, process metrics
- `pyobjc-framework-Cocoa` - macOS menu bar integration (NSStatusItem, AppKit)

## Architecture

```
main.py       Entry point, NSApplication setup
tray.py       Menu bar icon with color-coded CPU %
panel.py      Dark dropdown panel with stats and network graph
monitor.py    Background thread polling metrics every 2s
cpu.py        CPU % overall, per-core P/E split, top processes
gpu.py        GPU utilization via ioreg (no sudo)
memory.py     RAM and swap usage via psutil
network.py    Network speed with 60s rolling history
config.py     User preferences (~/Library/Application Support/)
```

---

**LAB37**
