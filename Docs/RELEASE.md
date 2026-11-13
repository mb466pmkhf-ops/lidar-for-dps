# Releasing FrameScout to the App Store

The pipeline builds, signs and uploads to TestFlight from GitHub Actions. You only do the account
steps once, then each release is: push a tag, test the TestFlight build, press Submit.

## One-time setup (owner only)

1. **Join the Apple Developer Program** (developer.apple.com/programs, $99/year). The free Personal
   Team can't upload to TestFlight or the App Store.
2. **Pick the store name and bundle id.** The bundle id can't change after the first upload
   (Docs/DECISIONS.md D-001).
3. **Register the bundle id**: developer.apple.com → Certificates, IDs & Profiles → Identifiers → +
   → App IDs → App. Explicit bundle id. No extra capabilities are needed yet.
4. **Create the app** in App Store Connect → Apps → + → New App: iOS, the name, primary language,
   that bundle id, an SKU such as `framescout-ios`.
5. **Create an API key**: App Store Connect → Users and Access → Integrations → App Store Connect API
   → Team Keys → +. Name it `GitHub release`, role **Admin** (needed for cloud-managed signing).
   Download the `.p8` file (only possible once) and note the Key ID and the Issuer ID above the list.
6. **Add GitHub secrets**: repository → Settings → Secrets and variables → Actions → New repository secret:
   - `ASC_KEY_ID` – the Key ID
   - `ASC_ISSUER_ID` – the Issuer ID
   - `ASC_KEY_P8` – the whole text of the `.p8` file, including the BEGIN/END lines
   - `APPLE_TEAM_ID` – developer.apple.com → Membership details → Team ID
   And under **Variables**: `IOS_BUNDLE_ID` if it differs from `com.framescout.app`.
7. **Approval gate (recommended)**: Settings → Environments → New environment `app-store` → Required
   reviewers → yourself. Each upload then waits for your click.
8. **Live database**: run the newest `web/supabase/schema.sql` in the Supabase SQL editor (adds
   `delete_my_account()`), and turn on Authentication → Settings → Leaked password protection.
9. **Privacy policy**: fill in the brackets in `Docs/PRIVACY.md`, publish it at a public address
   (e.g. GitHub Pages), and paste the address into App Store Connect → App Privacy and the app record.

## Each release

1. Tag the commit: `git tag v1.0.0 && git push origin v1.0.0` (or Actions → App Store release →
   Run workflow and type the version).
2. The workflow runs every check, archives a signed build and uploads it. Build numbers count up
   automatically.
3. About 15 minutes later the build appears in App Store Connect → TestFlight. Install it on your
   iPhone with the TestFlight app and check scanning, sign-in and sync on the device.
4. In App Store Connect, attach the build to the version, fill in What's New, and press
   **Add for Review** → **Submit**.

## What the checks cover

| Gate | Where |
| --- | --- |
| Xcode Release build, unsigned IPA | `build.yml` → iOS app |
| Core logic tests, Swift ↔ web parity, look sheet, GLB/USD validators | `build.yml` → Core logic tests |
| No high/critical advisories in shipped npm packages | `build.yml` → Release gates |
| Only allowed licences; notices file up to date | `scripts/third-party-notices.mjs` |
| Privacy manifest, export compliance, usage texts, account deletion | `scripts/check-store-rules.py` |
| Privacy manifest inside the signed bundle, code signature valid | `release-ios.yml` |

After adding or updating a web or desktop dependency, regenerate the notices:

```
cd web && npm ci && cd src-tauri && cargo metadata --format-version 1 --locked > /tmp/meta.json && cd ../..
node scripts/third-party-notices.mjs --cargo-metadata /tmp/meta.json
```

Not covered automatically: scanning, permissions and anything else that needs a real LiDAR iPhone
(test those on the TestFlight build).
