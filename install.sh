#!/usr/bin/env bash
#
# System Monitor installer: builds from source and installs to /Applications.
# One command, no Apple Developer account needed. Apple Silicon or Intel,
# macOS 14+.
#
#   ./install.sh
#
# Builds Release if a Developer ID certificate is on this Mac, otherwise an
# ad-hoc signed Debug build, which runs fine locally. The app needs no
# permissions at all, so there is nothing for the user to grant afterwards.

set -euo pipefail

cd "$(dirname "$0")"

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RED=$'\033[31m'; RST=$'\033[0m'
step() { printf "%s==>%s %s\n" "$GREEN$BOLD" "$RST" "$1"; }
die()  { printf "%sx  %s%s\n" "$RED" "$1" "$RST" >&2; exit 1; }

TEAM_ID="4D2U237VRC"
APP_NAME="System Monitor.app"
LOG=/tmp/system-monitor-build.log

# --- Preflight ---------------------------------------------------------------

step "Checking prerequisites"

os_major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$os_major" -ge 14 ] 2>/dev/null \
  || die "System Monitor requires macOS 14 or later. This Mac is $(sw_vers -productVersion)."

if ! xcodebuild -version >/dev/null 2>&1; then
  die "Full Xcode is required (Command Line Tools alone can't build this).
   Install Xcode from the App Store, then run:  sudo xcode-select -s /Applications/Xcode.app"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    step "Installing xcodegen via Homebrew"
    brew install xcodegen
  else
    die "xcodegen is required and Homebrew was not found.
   Install Homebrew from https://brew.sh then run:  brew install xcodegen"
  fi
fi

# --- Pick a configuration ----------------------------------------------------
# Prefer Release when the Developer ID cert is available, since that is the
# configuration releases ship. Without it, Debug plus ad-hoc signing still
# produces a working app on this machine.

if security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application: .*(${TEAM_ID})" >/dev/null; then
  CONFIG="Release"
  BUILD_ARGS=()
  step "Developer ID found: building Release (signed, hardened runtime)"
else
  CONFIG="Debug"
  BUILD_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic)
  step "No Developer ID on this Mac: building Debug with ad-hoc signing"
fi
# Either way this is a local build, not a notarized one. It runs here because a
# locally built app carries no quarantine attribute, so Gatekeeper never
# assesses it. Handing it to someone else is what needs scripts/release.sh.
printf "%s   Local build. To give it to another Mac, use scripts/release.sh.%s\n" "$DIM" "$RST"

# --- Build -------------------------------------------------------------------

step "Generating Xcode project"
xcodegen generate >/dev/null

step "Building (first build fetches Sparkle via SPM, so give it a minute)"
# The ${arr[@]+"${arr[@]}"} dance is not decoration: macOS ships bash 3.2, where
# expanding an empty array under `set -u` is an error rather than nothing.
xcodebuild -project SystemMonitor.xcodeproj -scheme SystemMonitor \
  -configuration "$CONFIG" -derivedDataPath build \
  ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} build >"$LOG" 2>&1 \
  || { tail -25 "$LOG"; die "Build failed. Full log: $LOG"; }

APP="build/Build/Products/$CONFIG/$APP_NAME"
[ -d "$APP" ] || die "Build reported success but $APP is missing."

# --- Install -----------------------------------------------------------------

step "Installing to /Applications"
pkill -f "$APP_NAME/Contents/MacOS" 2>/dev/null || true
sleep 1
rm -rf "/Applications/$APP_NAME"
# ditto rather than cp -R: it preserves the code signature and extended
# attributes, and a broken signature makes the app refuse to launch.
ditto "$APP" "/Applications/$APP_NAME"

step "Launching"
open "/Applications/$APP_NAME"

printf "\n%sInstalled.%s System Monitor is in your menu bar (a coloured CPU %%).\n" "$GREEN$BOLD" "$RST"
printf "  Click it for the panel. Gear icon opens Settings.\n"
printf "  Turn on %sLaunch at login%s in Settings if you want it back after a reboot.\n" "$BOLD" "$RST"

