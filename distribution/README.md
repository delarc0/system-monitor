# System Monitor — distribution

Release pipeline scaffolding for Sparkle auto-update. Mirrors Bark-mac's setup.

## State (2026-04-20)

- Sparkle package wired in `project.yml`; `SUFeedURL` + `SUPublicEDKey` placeholders in Info.plist.
- `appcast.xml` is a template — not yet hosted.
- **Public key is a placeholder.** Mint a real keypair before the first signed release (see below).
- Apple Developer ID is **pending** (shared status with Bark-mac). Until it's approved, we cannot ship real updates — Sparkle refuses to apply updates that aren't both EdDSA-signed and codesigned by a trusted identity.

## First-time key setup

```bash
# After a Debug build so Sparkle SPM is resolved:
./build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
# Prints the public key to paste into project.yml → SUPublicEDKey
# Private key is stored in the login keychain. Back it up:
./build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sysmon-sparkle-private.pem
# Store the exported PEM in 1Password. Re-import on a new machine with -f <file>.
```

## Release recipe (when Dev ID is approved)

Run from `apps/system-monitor`:

```bash
# 1. Bump version
sed -i '' 's/MARKETING_VERSION: "0.1.0"/MARKETING_VERSION: "0.2.0"/' project.yml
xcodegen

# 2. Archive + export with Developer ID
xcodebuild -project SystemMonitor.xcodeproj -scheme SystemMonitor -configuration Release \
  -archivePath build/SystemMonitor.xcarchive archive
xcodebuild -exportArchive -archivePath build/SystemMonitor.xcarchive \
  -exportPath build/export -exportOptionsPlist distribution/ExportOptions.plist

# 3. Notarize + staple
xcrun notarytool submit build/export/SystemMonitor.app --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple build/export/SystemMonitor.app

# 4. Zip + EdDSA-sign for Sparkle
ditto -c -k --sequesterRsrc --keepParent build/export/SystemMonitor.app build/SystemMonitor-0.2.0.zip
./build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update build/SystemMonitor-0.2.0.zip

# 5. Update appcast.xml with the new <item>, push to GH Pages, upload zip to GH Release
```

## Hosting

Target: GitHub Pages from the `system-monitor` repo, served at `delarc0.github.io/system-monitor/appcast.xml` (matches `SUFeedURL` in `project.yml`). Release zips live on GitHub Releases so they're cacheable without hammering Pages.
