# System Monitor: distribution

`./scripts/release.sh` is the whole pipeline. This file is what it can't do for you.

The feed is GitHub Pages (`delarc0.github.io/system-monitor/appcast.xml`, set as `SUFeedURL` in `project.yml`). Zips live on GitHub Releases.

## First-time setup

`./scripts/release.sh --check` reports what is missing. The Sparkle key is done (below); the rest is per Mac.

1. Signing: sign in to Xcode as the team's account holder (Settings > Accounts). Nothing else. The export signs as Developer ID through Apple's cloud signing, so no local certificate is needed. `--check` can't see this; the archive step fails if it's missing.
2. Notary profile: `xcrun notarytool store-credentials AC_NOTARY --apple-id erik@lab37.io --team-id 4D2U237VRC`, using an app-specific password from appleid.apple.com.

The Sparkle key is this app's own, separate from Bark's: `--account system-monitor` in LAB37 Studio's login keychain, with a backup at `~/.config/system-monitor/sparkle-ed25519.key`. Lose it and installed copies can never update again. To use it on another Mac: `generate_keys --account system-monitor -f <that file>`.

The first version with this key must be installed by hand, since nothing older can verify it. After that, every install updates itself.

## Cutting a release

```bash
./scripts/release.sh 0.5.0             # build and stage, pushes nothing
./scripts/release.sh 0.5.0 --publish   # the same, then ship it
```

`--publish` commits to main, creates the GitHub Release, then publishes the appcast. The appcast goes last so the feed never names a zip that isn't uploaded.
