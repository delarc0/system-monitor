#!/usr/bin/env bash
#
# System Monitor release pipeline:
#   archive -> Developer ID export -> notarize -> staple -> verify -> Sparkle-sign
#   -> appcast -> (with --publish) commit, GitHub Release, gh-pages
#
# Usage:
#   ./scripts/release.sh --check              preflight only: is this Mac release-ready?
#   ./scripts/release.sh 0.5.0                build and stage locally. Pushes nothing.
#   ./scripts/release.sh 0.5.0 --publish      the same, then ship it.
#
# First-time setup is in distribution/README.md.

set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="4D2U237VRC"
PROFILE="AC_NOTARY"
REPO="delarc0/system-monitor"
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

  if grep "REPLACE_WITH_SPARKLE_PUBLIC_KEY" project.yml >/dev/null 2>&1; then
    echo "  sparkle: public key is still a placeholder, see distribution/README.md"
    PREFLIGHT_OK=0
  else
    bold "sparkle: public key set"
  fi

  if gh auth status >/dev/null 2>&1; then
    bold "gh: authenticated"
  else
    echo "  gh: not authenticated (gh auth login)"; PREFLIGHT_OK=0
  fi

  [ "$PREFLIGHT_OK" = 1 ] || fail "preflight failed, fix the items above"
  bold "preflight OK"
}

if [ "${1:-}" = "--check" ]; then
  preflight
  exit 0
fi

VERSION="${1:-}"
PUBLISH=0
[ "${2:-}" = "--publish" ] && PUBLISH=1
[ -n "$VERSION" ] || fail "usage: ./scripts/release.sh <version> [--publish]   (or --check)"
echo "$VERSION" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' >/dev/null \
  || fail "version must look like 1.2.3, got '$VERSION'"

preflight

OLD="$(grep -E '^\s*MARKETING_VERSION:' project.yml | sed -E 's/.*"(.*)".*/\1/')"
[ -n "$OLD" ] || fail "could not read MARKETING_VERSION from project.yml"
BUILD="$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"(.*)".*/\1/')"
[ -n "$BUILD" ] || fail "could not read CURRENT_PROJECT_VERSION from project.yml"

step "Version $OLD -> $VERSION"
if [ "$OLD" != "$VERSION" ]; then
  # Sparkle compares the build number, so one that doesn't move is an update nobody gets.
  sed -i '' "s/MARKETING_VERSION: \"$OLD\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
  sed -i '' "s/CURRENT_PROJECT_VERSION: \"$BUILD\"/CURRENT_PROJECT_VERSION: \"$((BUILD + 1))\"/" project.yml
  BUILD=$((BUILD + 1))
  grep "MARKETING_VERSION: \"$VERSION\"" project.yml >/dev/null || fail "version bump did not apply"
  grep "CURRENT_PROJECT_VERSION: \"$BUILD\"" project.yml >/dev/null || fail "build bump did not apply"
fi
bold "version $VERSION, build $BUILD"

step "Generating project"
xcodegen generate >/dev/null

step "Archiving"
rm -rf build/SystemMonitor.xcarchive build/export
xcodebuild -project SystemMonitor.xcodeproj -scheme SystemMonitor -configuration Release \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -archivePath build/SystemMonitor.xcarchive archive >"$LOG" 2>&1 \
  || { tail -25 "$LOG"; fail "archive failed. Full log: $LOG"; }

step "Exporting with Developer ID"
xcodebuild -exportArchive -archivePath build/SystemMonitor.xcarchive \
  -exportPath build/export -exportOptionsPlist distribution/ExportOptions.plist >>"$LOG" 2>&1 \
  || { tail -25 "$LOG"; fail "export failed. Full log: $LOG"; }

APP="build/export/$APP_NAME"
[ -d "$APP" ] || fail "export succeeded but $APP is missing"

mkdir -p build/releases
ZIP="build/releases/SystemMonitor-$VERSION.zip"

step "Notarizing"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SUBMIT="$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" 2>&1)" \
  || { printf '%s\n' "$SUBMIT"; fail "notarytool submit failed"; }
SUBMISSION="$(printf '%s\n' "$SUBMIT" | awk '/^  id:/ {print $2; exit}')"
[ -n "$SUBMISSION" ] || { printf '%s\n' "$SUBMIT"; fail "no submission id in notarytool output"; }
bold "submitted $SUBMISSION, waiting on Apple"
# `wait` dies on a network blip while the submission keeps processing, so it is retried.
for attempt in $(seq 1 40); do
  xcrun notarytool wait "$SUBMISSION" --keychain-profile "$PROFILE" >>"$LOG" 2>&1 && break
  echo "  wait dropped (attempt $attempt), retrying in 30s"
  sleep 30
done
STATUS="$(xcrun notarytool info "$SUBMISSION" --keychain-profile "$PROFILE" 2>&1 | awk '/status:/ {print $2; exit}')"
if [ "$STATUS" != "Accepted" ]; then
  xcrun notarytool log "$SUBMISSION" --keychain-profile "$PROFILE" || true
  fail "notarization status: ${STATUS:-unknown}"
fi

step "Stapling"
xcrun stapler staple "$APP" >>"$LOG" 2>&1 || { tail -20 "$LOG"; fail "stapling failed"; }

step "Verifying"
codesign --verify --deep --strict "$APP" || fail "code signature does not verify"
spctl -a -vvv "$APP" 2>&1 | grep "source=Notarized Developer ID" >/dev/null \
  || fail "Gatekeeper did not report a notarized Developer ID app"
bold "signature verifies, Gatekeeper accepts it as Notarized Developer ID"

# Re-zip so the archive holds the stapled ticket, and sign that final zip: Sparkle
# checks the signature against the exact bytes it downloads.
step "Sparkle-signing"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SIGN_UPDATE="$(find build/SourcePackages/artifacts -type f -name sign_update 2>/dev/null | head -1)"
[ -n "$SIGN_UPDATE" ] || fail "sign_update not found under build/SourcePackages"
ED_LINE="$("$SIGN_UPDATE" --account system-monitor "$ZIP")"
[ -n "$ED_LINE" ] || fail "sign_update returned nothing, is the private key in this Mac's keychain?"

step "Appcast"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/SystemMonitor-${VERSION}.zip"
ITEM="$(mktemp)"
cat > "$ITEM" <<EOF

        <item>
            <title>Version ${VERSION}</title>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
            <enclosure
                url="${URL}"
                ${ED_LINE}
                type="application/octet-stream" />
        </item>
EOF
sed -i '' "/<language>en<\/language>/r ${ITEM}" distribution/appcast.xml
rm -f "$ITEM"
xmllint --noout distribution/appcast.xml || fail "appcast.xml is not valid XML after insertion"
bold "distribution/appcast.xml updated"

if [ "$PUBLISH" != 1 ]; then
  step "Staged only, nothing pushed"
  cat <<EOF
  ${ZIP} is signed, notarized and stapled.
  project.yml and distribution/appcast.xml carry the staging, uncommitted.

  To publish, reset the staging and re-run:
    git checkout -- project.yml distribution/appcast.xml
    ./scripts/release.sh ${VERSION} --publish
EOF
  exit 0
fi

step "Publishing: release commit"
git add project.yml distribution/appcast.xml
git commit -m "Release ${VERSION}"
trap 'printf "\033[1;31mPUBLISH INCOMPLETE:\033[0m the release commit exists. Check origin/main, the GitHub Release and gh-pages to see how far it got.\n" >&2' ERR
git push origin main

step "Publishing: GitHub Release"
gh release create "v${VERSION}" "$ZIP" --repo "$REPO" --title "System Monitor ${VERSION}" \
  --notes "Signed and notarized. Unzip and move to Applications. Existing installs update from the panel."

# The appcast goes last: a feed that names a zip not uploaded yet breaks every update check.
step "Publishing: appcast to gh-pages"
WT="build/ghpages-wt"
rm -rf "$WT"
git worktree prune
if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
  git fetch origin gh-pages
  git worktree add --detach "$WT" FETCH_HEAD
else
  git worktree add --orphan -b gh-pages "$WT"
fi
cp distribution/appcast.xml "$WT/appcast.xml"
touch "$WT/.nojekyll"
git -C "$WT" add appcast.xml .nojekyll
git -C "$WT" commit -m "appcast: ${VERSION}" >/dev/null
git -C "$WT" push origin HEAD:refs/heads/gh-pages
git worktree remove --force "$WT"
gh api "repos/${REPO}/pages" >/dev/null 2>&1 || \
  gh api "repos/${REPO}/pages" -X POST -f "source[branch]=gh-pages" -f "source[path]=/" >/dev/null

step "Done"
cat <<EOF
  System Monitor ${VERSION} (build ${BUILD}) released.
    Release: https://github.com/${REPO}/releases/tag/v${VERSION}
    Appcast: https://delarc0.github.io/system-monitor/appcast.xml
EOF
