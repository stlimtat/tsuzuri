# TestFlight release: Lead checklist

The **Release (TestFlight)** workflow ([`.github/workflows/release.yml`](../../.github/workflows/release.yml)) archives the iOS app, signs it and uploads it to App Store Connect. It runs only when started by hand on `main` (Actions → Release (TestFlight) → Run workflow).

Each upload gets:

- **Build number** = the workflow run number (`CURRENT_PROJECT_VERSION`).
- **Commit** = the full commit SHA, in `Info.plist` as `TsuzuriCommit` (from the `TSUZURI_COMMIT` build setting). The workflow fails before uploading if the archived app's `Info.plist` lacks it ([`scripts/verify-archive.sh`](../../scripts/verify-archive.sh)).

The debug Library screen shows both at the bottom, e.g. `Build 42 · 0123abc`. Local and unsigned CI builds show `Build 1 · dev`.

The steps below are one-time and only the Lead can do them. Do them in order.

## 1. Apple Developer Program

- [ ] Enrol in the [Apple Developer Program](https://developer.apple.com/programs/enroll/) (paid, yearly). Note your **Team ID** (Membership details); the workflow reads it from the provisioning profile, so it is not a secret.

## 2. Bundle ID and iCloud container

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list):

- [ ] Register the iCloud container **`iCloud.net.stlim.tsuzuri`** (Identifiers → iCloud Containers).
- [ ] Register the App ID **`net.stlim.tsuzuri`** (explicit, not wildcard). This must match the `TSUZURI_BUNDLE_ID` build setting in `Apps/iOS/Tsuzuri.xcodeproj`.
- [ ] Enable the **iCloud** capability on it, with CloudKit, and assign the container `iCloud.net.stlim.tsuzuri`.

## 3. App Store Connect app record

- [ ] In [App Store Connect](https://appstoreconnect.apple.com/apps) → Apps → **+** → New App: platform iOS, name Tsuzuri, primary language English, bundle ID `net.stlim.tsuzuri`, any SKU (e.g. `tsuzuri`).

## 4. Apple Distribution certificate (.p12)

- [ ] On your Mac, Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority (saved to disk).
- [ ] Certificates → **+** → **Apple Distribution**, upload the request, download and double-click the `.cer`.
- [ ] In Keychain Access → My Certificates, right-click **Apple Distribution: …** → Export as `distribution.p12` with a strong password (keep the password in 1Password).

## 5. App Store provisioning profile

- [ ] Profiles → **+** → Distribution → **App Store Connect**, App ID `net.stlim.tsuzuri`, the Apple Distribution certificate from step 4. Name it e.g. `Tsuzuri App Store`. Download `Tsuzuri_App_Store.mobileprovision`.
- [ ] If you later add a capability or renew the certificate, regenerate the profile and update its secret (step 8).

## 6. App Store Connect API key

- [ ] App Store Connect → Users and Access → Integrations → **App Store Connect API** → Team Keys → **+**, name `Tsuzuri CI`, access **App Manager**.
- [ ] Download `AuthKey_<KEY ID>.p8` (only downloadable once). Note the **Key ID** and the **Issuer ID** shown above the key list.

## 7. CloudKit production schema

The record schema is created in the CloudKit **development** environment by the live backend (#10) first. TestFlight builds use the **production** environment, which starts empty (ADR 0007: deploy the schema before a TestFlight build ships).

- [ ] Run a development build that saves Works and files (after #10), so every record type and field exists in development.
- [ ] [CloudKit Console](https://icloud.developer.apple.com/) → `iCloud.net.stlim.tsuzuri` → Schema → **Deploy Schema Changes…** to production.
- [ ] Repeat whenever `ComicSchema` changes the record schema, before shipping the build that needs it.

## 8. GitHub secrets

The workflow reads exactly these six repository secrets (Settings → Secrets and variables → Actions). Your `gh` runs through the 1Password plugin, so set each with `op plugin run -- gh secret set NAME < file`. Binary files are stored base64-encoded. Run from the folder holding the downloaded files, then delete the intermediate files.

| Secret | Contents |
|---|---|
| `APPLE_DISTRIBUTION_CERTIFICATE_P12_BASE64` | `distribution.p12` (step 4), base64 |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | the `.p12` export password |
| `APP_STORE_PROVISIONING_PROFILE_BASE64` | the `.mobileprovision` (step 5), base64 |
| `APP_STORE_CONNECT_API_KEY_P8` | `AuthKey_<KEY ID>.p8` (step 6), as is (text) |
| `APP_STORE_CONNECT_API_KEY_ID` | the Key ID, e.g. `ABC123DEFG` |
| `APP_STORE_CONNECT_API_ISSUER_ID` | the Issuer ID (a UUID) |

```bash
base64 -i distribution.p12 -o distribution.p12.b64
base64 -i Tsuzuri_App_Store.mobileprovision -o profile.b64
op plugin run -- gh secret set APPLE_DISTRIBUTION_CERTIFICATE_P12_BASE64 --repo stlimtat/tsuzuri < distribution.p12.b64
op plugin run -- gh secret set APP_STORE_PROVISIONING_PROFILE_BASE64 --repo stlimtat/tsuzuri < profile.b64
op plugin run -- gh secret set APP_STORE_CONNECT_API_KEY_P8 --repo stlimtat/tsuzuri < AuthKey_ABC123DEFG.p8

# Values without a file: gh prompts for them when stdin is a terminal (nothing lands in shell history).
op plugin run -- gh secret set APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD --repo stlimtat/tsuzuri
op plugin run -- gh secret set APP_STORE_CONNECT_API_KEY_ID --repo stlimtat/tsuzuri
op plugin run -- gh secret set APP_STORE_CONNECT_API_ISSUER_ID --repo stlimtat/tsuzuri

rm distribution.p12.b64 profile.b64   # keep the originals in 1Password, not on disk
op plugin run -- gh secret list --repo stlimtat/tsuzuri
```

The secrets exist only in GitHub. During the job they are written to the runner's temp folder and a temporary keychain, and the last step deletes both even when an earlier step fails.

## 9. First upload and internal testing

- [ ] Actions → **Release (TestFlight)** → Run workflow, branch `main`.
- [ ] Wait for App Store Connect to finish processing the build (email, usually 5–30 minutes).
- [ ] App Store Connect → Tsuzuri → TestFlight → Internal Testing → **+** create a group (e.g. `Lead`), add yourself as an internal tester, and add the build. Internal builds need no Beta App Review.
- [ ] Install **TestFlight** on your iPhone, accept the invite, install Tsuzuri.
- [ ] Open it and check the debug screen shows `Build <run number> · <first 7 characters of the commit>`.

## Local builds

This Mac is Intel (x86_64): simulator builds must include x86_64. `scripts/build-app.sh` already builds every simulator architecture (`ONLY_ACTIVE_ARCH=NO`). An unsigned simulator app needs `codesign -f -s - Tsuzuri.app` before `xcrun simctl install`. To regenerate the app icon after changing `docs/assets/logo.svg`, run `scripts/render-app-icon.sh` and commit the PNG.
