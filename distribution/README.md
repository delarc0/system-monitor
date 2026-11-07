# System Monitor: distribution

`./scripts/release.sh` is the whole pipeline. This file is what it can't do for you.

The feed is GitHub Pages (`delarc0.github.io/system-monitor/appcast.xml`, set as `SUFeedURL` in `project.yml`). Zips live on GitHub Releases.

## First-time setup

Not done yet on any Mac. `./scripts/release.sh --check` reports what is missing.

1. Developer ID certificate: Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application.
2. Notary profile: `xcrun notarytool store-credentials AC_NOTARY --apple-id <you@lab37.io> --team-id 4D2U237VRC`, using an app-specific password from appleid.apple.com.
3. This app's own Sparkle key, separate from Bark's. After any build:
   ```bash
   ./build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account system-monitor
   ```
   Set the printed public key as `SUPublicEDKey` in `project.yml`. The private key stays in the login keychain. Export it once with `-x` and keep it in the password manager: lose it and installed copies can never update again.
4. Set `SUEnableAutomaticChecks` to `YES` in `project.yml`.

The first version with a real key must be installed by hand, since nothing older can verify it. After that, every install updates itself.

## Cutting a release

```bash
./scripts/release.sh 0.5.0             # build and stage, pushes nothing
./scripts/release.sh 0.5.0 --publish   # the same, then ship it
```

`--publish` commits to main, creates the GitHub Release, then publishes the appcast. The appcast goes last so the feed never names a zip that isn't uploaded.
