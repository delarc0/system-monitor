#!/usr/bin/env bash
#
# System Monitor release pipeline:
#   archive -> Developer ID export -> notarize -> staple -> verify -> zip
#
# Usage:
#   ./scripts/release.sh --check          preflight only: is this Mac release-ready?
#   ./scripts/release.sh 0.3.0            build, notarize and stage locally. Pushes nothing.
#
# This deliberately stops at a staged, notarized zip. Sparkle auto-update is NOT
# finished (the EdDSA key in project.yml is a placeholder and no appcast is
# hosted), so there is no publish step to run yet. Finish those two things first,
# then extend this script; see distribution/README.md.
#
# One-time machine setup:
#   1. Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#   2. xcrun notarytool store-credentials AC_NOTARY \
#        --apple-id <you@lab37.io> --team-id 4D2U237VRC
#      (the password is an app-specific password from appleid.apple.com)

set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="4D2U237VRC"
PROFILE="AC_NOTARY"
APP_NAME="System Monitor.app"
LOG=/tmp/system-monitor-release.log

bold() { printf '  \033[1m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

PREFLIGHT_OK=1

preflight() {
  step "Preflight"
  [ -f project.yml ] || fail "project.yml not found (this script must live in scripts/ under the repo root)"

  if command -v xcodegen >/dev/null 2>&1; then
    bold "xcodegen: present"
  else
    echo "  xcodegen: MISSING (brew install xcodegen)"; PREFLIGHT_OK=0
  fi

  if security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application: .*(${TEAM_ID})" >/dev/null; then
    bold "cert: Developer ID Application (${TEAM_ID}) present"
  else
    echo "  cert: MISSING - Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application"
    PREFLIGHT_OK=0
  fi

  if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    bold "notary: keychain profile ${PROFILE} works"
  else
    echo "  notary: MISSING - xcrun notarytool store-credentials ${PROFILE} --apple-id <you> --team-id ${TEAM_ID}"
    PREFLIGHT_OK=0
  fi

  if [ -n "$(git status --porcelain)" ]; then
    echo "  git: working tree DIRTY - commit or stash first, releases must be reproducible"
    PREFLIGHT_OK=0
  else
    bold "git: clean tree at $(git rev-parse --short HEAD)"
  fi

  # Not fatal: you can cut a signed, notarized build without Sparkle. It just
  # can't auto-update anyone.
  if grep "REPLACE_WITH_SPARKLE_PUBLIC_KEY" project.yml >/dev/null 2>&1; then
    printf '  \033[33msparkle: public key is still a placeholder, so this build cannot auto-update\033[0m\n'
  else
    bold "sparkle: public key set"
  fi

  [ "$PREFLIGHT_OK" = 1 ] || fail "preflight failed, fix the items above"
  bold "preflight OK"
}

if [ "${1:-}" = "--check" ]; then
  preflight
  exit 0
fi

NEW="${1:-}"
[ -n "$NEW" ] || fail "usage: ./scripts/release.sh <version>   (or --check)"
echo "$NEW" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' >/dev/null \
  || fail "version must look like 1.2.3, got '$NEW'"

preflight

OLD="$(grep -E '^\s*MARKETING_VERSION:' project.yml | sed -E 's/.*"(.*)".*/\1/')"
[ -n "$OLD" ] || fail "could not read MARKETING_VERSION from project.yml"

step "Version $OLD -> $NEW"
if [ "$OLD" != "$NEW" ]; then
  # Fail loudly rather than shipping the old number because a sed silently
  # matched nothing.
  grep "MARKETING_VERSION: \"$OLD\"" project.yml >/dev/null || fail "MARKETING_VERSION \"$OLD\" not found"
  sed -i '' "s/MARKETING_VERSION: \"$OLD\"/MARKETING_VERSION: \"$NEW\"/" project.yml
  BUILD_NUM="$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"(.*)".*/\1/')"
  sed -i '' "s/CURRENT_PROJECT_VERSION: \"$BUILD_NUM\"/CURRENT_PROJECT_VERSION: \"$((BUILD_NUM + 1))\"/" project.yml
  bold "project.yml bumped (commit this after the release succeeds)"
else
  bold "already at $NEW, rebuilding"
fi

step "Generating project"
xcodegen generate >/dev/null

step "Archiving"
rm -rf build/SystemMonitor.xcarchive build/export
xcodebuild -project SystemMonitor.xcodeproj -scheme SystemMonitor -configuration Release \
  -archivePath build/SystemMonitor.xcarchive archive >"$LOG" 2>&1 \
  || { tail -25 "$LOG"; fail "archive failed. Full log: $LOG"; }

step "Exporting with Developer ID"
xcodebuild -exportArchive -archivePath build/SystemMonitor.xcarchive \
  -exportPath build/export -exportOptionsPlist distribution/ExportOptions.plist >>"$LOG" 2>&1 \
  || { tail -25 "$LOG"; fail "export failed. Full log: $LOG"; }

APP="build/export/$APP_NAME"
[ -d "$APP" ] || fail "export succeeded but $APP is missing"

step "Zipping"
mkdir -p build/releases
ZIP="build/releases/SystemMonitor-$NEW.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

step "Notarizing (this waits on Apple, usually a couple of minutes)"
# Submit exactly once and inspect the captured output. Piping straight into a
# check would mean submitting twice.
NOTARY_OUT="$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait 2>&1)"
printf '%s\n' "$NOTARY_OUT" >>"$LOG"
printf '%s\n' "$NOTARY_OUT" | tail -4
printf '%s\n' "$NOTARY_OUT" | grep "status: Accepted" >/dev/null \
  || fail "notarization was not accepted. Full log: $LOG"

step "Stapling"
xcrun stapler staple "$APP" >>"$LOG" 2>&1 || { tail -20 "$LOG"; fail "stapling failed, so notarization did not succeed"; }

step "Verifying"
codesign --verify --deep --strict "$APP" || fail "code signature does not verify"
spctl -a -vvv "$APP" 2>&1 | grep "source=Notarized Developer ID" >/dev/null \
  || fail "Gatekeeper did not report a notarized Developer ID app"
bold "signature verifies, Gatekeeper accepts it as Notarized Developer ID"

# Re-zip so the archive contains the stapled ticket. Without this the zip you
# hand out still triggers a Gatekeeper check on a machine that is offline.
step "Re-zipping with the stapled ticket"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

printf '\n\033[1;32mStaged:\033[0m %s\n' "$ZIP"
printf '  Notarized and stapled. Copy it to any Mac and it opens with no warning.\n'
printf '  Nothing was pushed. To install it here:  ./install.sh\n'
if grep "REPLACE_WITH_SPARKLE_PUBLIC_KEY" project.yml >/dev/null 2>&1; then
  printf '\n  Auto-update is still not wired. See distribution/README.md.\n'
fi
