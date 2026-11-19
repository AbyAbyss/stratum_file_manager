# Releasing Stratum

Stratum uses [Semantic Versioning](https://semver.org). The version lives in one place,
`MARKETING_VERSION` in `project.yml`. It is what Settings → About shows, and GitHub Actions
releases exactly that version, triggered by pushing its tag or by a button.

## Versioning

Versions are `MAJOR.MINOR.PATCH`; release tags are that version prefixed with `v`, for example
`v1.0.0`.

- **PATCH** (`1.0.0` → `1.0.1`): bug fixes and small tweaks.
- **MINOR** (`1.0.x` → `1.1.0`): a significant change or new feature that stays compatible with
  existing data and settings. Resets PATCH to 0.
- **MAJOR** (`1.x.y` → `2.0.0`): a major change, such as a redesign or an incompatible data
  format. Resets MINOR and PATCH to 0.

## Cutting a release

1. **Bump the version.** Set `MARKETING_VERSION` in `project.yml` and merge it to `main` with the
   changes it ships.
2. **Release it**, either way:
   - **Button:** GitHub → **Actions** → **Release** → **Run workflow** on `main`. The tag is
     created for you. The run stops if the tag already exists (you forgot to bump) or if it
     isn't started from `main`.
   - **Tag:**
     ```sh
     git checkout main && git pull
     git tag v1.0.0
     git push origin v1.0.0
     ```
     The run stops if the tag doesn't match `MARKETING_VERSION`.

Either trigger runs [`.github/workflows/release.yml`](../.github/workflows/release.yml), which:

1. Reads the version from `project.yml` and checks the Sparkle public key is set.
2. Generates the Xcode project with XcodeGen and runs the unit tests (a failure stops the release).
3. Builds `Stratum.app` in Release, Developer ID signed when the signing secrets exist, ad-hoc
   otherwise.
4. Packages `Stratum-<version>.dmg`, then notarizes and staples it (signed builds only).
5. Signs the DMG for Sparkle and writes `appcast.xml`.
6. Creates the GitHub Release, attaches the DMG and the appcast, and generates notes from the
   commits since the previous tag.

To undo a mistaken release, delete the GitHub Release and the tag
(`git push --delete origin v1.0.0`), then re-tag.

## Building a release locally

```sh
xcodegen generate
xcodebuild -project Stratum.xcodeproj -scheme Stratum -configuration Release \
  -derivedDataPath build build
APP="build/Build/Products/Release/Stratum.app"
mkdir dmg && cp -R "$APP" dmg/ && ln -s /Applications dmg/Applications
hdiutil create -volname Stratum -srcfolder dmg -ov -format UDZO Stratum-local.dmg
```

## Auto-updates (Sparkle)

Stratum updates itself with [Sparkle](https://sparkle-project.org). Each release attaches an
`appcast.xml`, and the app reads the copy on the latest release:

```
https://github.com/AbyAbyss/stratum_file_manager/releases/latest/download/appcast.xml
```

Sparkle only installs an update whose EdDSA signature matches the public key built into the
running app. The public key is `SPARKLE_PUBLIC_KEY` in `project.yml`, and the matching private key
is the `SPARKLE_PRIVATE_KEY` repository secret. Stratum currently shares Yankit's key pair. A build
with an empty `SPARKLE_PUBLIC_KEY` has no updater (no "Check for Updates…" item), and the release
workflow refuses to run without one, so a release can't ship without an updater by accident.

The steps below are the one-time setup, for reference or for switching to a key of Stratum's own.

1. Download the Sparkle release matching the package version from
   [its releases page](https://github.com/sparkle-project/Sparkle/releases) and run
   `./bin/generate_keys`. It stores the private key in your login Keychain and prints the public
   key.
2. Paste the public key into `SPARKLE_PUBLIC_KEY` in `project.yml`.
3. Export the private key with `./bin/generate_keys -x sparkle_private_key`, save the file's
   contents as the `SPARKLE_PRIVATE_KEY` repository secret (Settings → Secrets and variables →
   Actions), then delete the file. Keep the Keychain copy: **if you lose the private key,
   installed copies can never update again.**

Sharing one key pair between apps works, but separate keys per app are Sparkle's recommendation:
one leaked key then doesn't compromise every app. To switch Stratum to its own key later, generate
a new pair, update `SPARKLE_PUBLIC_KEY` and the `SPARKLE_PRIVATE_KEY` secret, and note that copies
already installed with the old key will not accept updates signed with the new one.

The first release with a key is the first one that can update itself. Sparkle asks on the second
launch whether to check automatically.

## Signing and notarization

Without a paid Apple Developer account the CI build is **unsigned**. It runs, but on first launch
macOS Gatekeeper blocks it and the user must approve it under System Settings → Privacy &
Security → **Open Anyway**. Signing and notarizing removes that friction.

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) ($99/year).
2. In Xcode → Settings → Accounts → Manage Certificates, create a **Developer ID Application**
   certificate. Export it from Keychain Access as a `.p12` with a password.
3. Add these repository secrets; the workflow's signing and notarization steps switch on by
   themselves once they exist:

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | base64 of the exported `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` export password |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | your 10-character Team ID |
| `APPLE_APP_PASSWORD` | an [app-specific password](https://support.apple.com/102654) |

The hardened runtime is only enabled for these signed builds. It enforces library validation, so
an ad-hoc build with it can't load the embedded Sparkle framework and quits at launch.

## Release checklist

- [ ] `main` builds and all tests pass.
- [ ] User-facing changes read clearly in commit messages: they become the release notes.
- [ ] Decide the bump (major, minor or patch), set `MARKETING_VERSION`, merge to `main`.
- [ ] **Run workflow**, or `git tag vX.Y.Z && git push origin vX.Y.Z`.
- [ ] Watch the **Actions** run finish green.
- [ ] On the **Releases** page, check the DMG and `appcast.xml` are attached and the notes look right.
- [ ] From an older install, use **Check for Updates…** and confirm it updates.
