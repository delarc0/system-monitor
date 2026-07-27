# System Monitor: distribution

Release pipeline scaffolding for Sparkle auto-update. Mirrors Bark-mac's setup.

## State (2026-07-27)

- Sparkle package wired in `project.yml`, which is also where `SUFeedURL`,
  `SUPublicEDKey` and `SUEnableAutomaticChecks` are set. `SystemMonitor/Info.plist`
  is generated from it by XcodeGen, so edit `project.yml`, never the plist.
- **Developer ID is available.** `Developer ID Application: LAB37 MEDIA AB (4D2U237VRC)`
  is in the login keychain, and Release is configured to sign with it
  (`CODE_SIGN_IDENTITY: "Developer ID Application"`, `DEVELOPMENT_TEAM: 4D2U237VRC`).
  The old "pending Apple approval" note was stale.
- **Public key is still a placeholder.** Mint a real keypair before the first
  signed release (see below). Until then `SUEnableAutomaticChecks` is `NO`, so the
  app doesn't prompt to auto-update or fetch a feed that isn't hosted yet.
- `appcast.xml` is a template, not yet hosted.

### Remaining before a first release

1. Mint the Sparkle keypair and paste the public key into `project.yml`.
2. Host `appcast.xml` (GitHub Pages, see Hosting) and flip `SUEnableAutomaticChecks` to `YES`.
3. Create the `AC_NOTARY` keychain profile: `xcrun notarytool store-credentials`.

## First-time key setup

```bash
# After a Debug build so Sparkle SPM is resolved:
./build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
# Prints the public key to paste into project.yml → SUPublicEDKey
# Private key is stored in the login keychain. Back it up:
./build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sysmon-sparkle-private.pem
# Store the exported PEM in 1Password. Re-import on a new machine with -f <file>.
```

## Release recipe

Run from `apps/system-monitor`. Note the built bundle is `System Monitor.app`
(with a space) while the target and scheme remain `SystemMonitor`.

```bash
OLD=0.2.0
NEW=0.3.0

# 1. Bump version. Fail loudly rather than shipping the old version number
#    because a silent no-op sed didn't match.
grep -q "MARKETING_VERSION: \"$OLD\"" project.yml || { echo "MARKETING_VERSION $OLD not found"; exit 1; }
sed -i '' "s/MARKETING_VERSION: \"$OLD\"/MARKETING_VERSION: \"$NEW\"/" project.yml
xcodegen generate

# 2. Archive + export with Developer ID
xcodebuild -project SystemMonitor.xcodeproj -scheme SystemMonitor -configuration Release \
  -archivePath build/SystemMonitor.xcarchive archive
xcodebuild -exportArchive -archivePath build/SystemMonitor.xcarchive \
  -exportPath build/export -exportOptionsPlist distribution/ExportOptions.plist

# 3. Notarize + staple
xcrun notarytool submit "build/export/System Monitor.app" --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple "build/export/System Monitor.app"

# 4. Zip into a release directory, then let Sparkle build the appcast from it.
#    generate_appcast signs each archive AND writes the matching length +
#    sparkle:edSignature into the <item>. Doing it by hand with sign_update
#    means one mistyped attribute silently breaks every client's update check.
SPARKLE_BIN=$(find build/SourcePackages/artifacts -type d -name bin -path '*[Ss]parkle*' | head -1)
mkdir -p build/releases
ditto -c -k --sequesterRsrc --keepParent \
  "build/export/System Monitor.app" "build/releases/SystemMonitor-$NEW.zip"
"$SPARKLE_BIN/generate_appcast" build/releases

# 5. Copy the generated appcast over distribution/appcast.xml, push it to GH
#    Pages, and upload the zip to a GH Release.
cp build/releases/appcast.xml distribution/appcast.xml
```

`generate_appcast` reads the private key from the login keychain (the one minted
above) and reuses signatures for archives it has already seen, so re-running it
over `build/releases` is safe.

## Hosting

Target: GitHub Pages from the `system-monitor` repo, served at `delarc0.github.io/system-monitor/appcast.xml` (matches `SUFeedURL` in `project.yml`). Release zips live on GitHub Releases so they're cacheable without hammering Pages.
