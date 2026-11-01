# Store release runbook

Operational notes from the 1.1.0 and 1.2.0 releases. Keep this file updated
when a tool behaves differently from its docs.

## Version discipline

- One source of truth for the app build: `pubspec.yaml` (`1.2.0+19`).
- iOS takes the Runner build from `FLUTTER_BUILD_NUMBER`; the PacketTunnel
  extension reads `CURRENT_PROJECT_VERSION` from
  `ios/Runner.xcodeproj/project.pbxproj`. Bump both.
- A build number that reached App Store Connect or Play can never be reused.
  Check both stores before bumping or re-uploading.

## Google Play

Internal testing is the "app tester" channel. Upload to the `internal` track and
commit; testers already configured in Play Console receive it immediately, no
review. Production stays on its own track and is unaffected.

The service-account path through `gpd` fails with a 403 quota-project error.
Use ADC plus the quota header instead:

```bash
TOKEN=$(gcloud auth application-default print-access-token)
AUTH="Authorization: Bearer $TOKEN"
QUOTA="x-goog-user-project: bionic-obelisk-377111"
BASE="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/app.bulbvpn.com"
```

Edit lifecycle:

1. `POST $BASE/edits` → edit id.
2. Upload the AAB to the **upload** host (not the JSON host):
   `POST https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/app.bulbvpn.com/edits/$EDIT/bundles?uploadType=media`
3. `PUT $BASE/edits/$EDIT/tracks/production` with the release.
4. `POST $BASE/edits/$EDIT:validate`, then `POST $BASE/edits/$EDIT:commit`.

Gotchas:

- **zsh eats `:c`.** `$EDIT:commit` expands to `...<id>ommit` and returns an
  HTML 404. Always write `${EDIT}:commit`.
- Edits are transactional. A bundle upload that is not committed disappears
  when the edit is discarded or expires.
- The app is a **draft app** until its first production release is published.
  Play rejects `completed` releases for draft apps with *"Only releases with
  status draft may be created on draft app."* Stage a draft release, commit,
  then send it for review in Play Console. After the first approval the API
  can publish normally. The `PUT` for a `completed` release is accepted
  silently; only `edits:validate` reports the draft-app error, so validate
  before trusting a track update.
- Read the track back in a fresh edit after committing; the commit response
  itself does not prove the release landed.
- The API cannot submit a first release for review. In Play Console open
  Test and release → Production → Releases → **Edit release** → **Next** →
  **Save** ("Preview and confirm"), then Publishing overview →
  **Submit N changes for review**. Until the store-setup checklist is 100%
  complete the button stays disabled with *"To send changes for review,
  complete the required steps in the app dashboard."*
- **Store settings** is part of that checklist. App category (Tools) and a
  contact email are the two required fields; each dialog saves its own change
  ("Change published" for contact details, "Change saved" for category).
- The `tracks` PUT does not set distribution countries. The console's
  Countries/regions tab starts at 0: check the select-all header row to enter
  edit mode, then **Save**. The track summary must read
  `N countries / regions` before submitting.
- Submission first sits in *"Changes in review — Running quick checks"* (up to
  ~15 min) before it goes to Google review. Managed publishing is off, so an
  approved release rolls out on its own.
- Listing `images` are **not** part of the `Listing` resource. Upload each
  file to
  `POST /upload/.../edits/$EDIT/listings/en-US/{icon|featureGraphic|phoneScreenshots}?uploadType=media`,
  then verify with
  `GET $BASE/edits/$EDIT/listings/en-US/phoneScreenshots` (an `images.list`
  endpoint; `listings.get` never shows images). Uploads append, so delete
  stale entries with `DELETE .../listings/en-US/phoneScreenshots/{imageId}`.
  Play allows at most 8 screenshots per type.

## App Store Connect

- App id `6822892688`.
- Upload: `asc builds upload --app 6822892688 --ipa build/ios/ipa/BULBVPN.ipa --wait`.
  The build is VALID minutes after the upload reports committed.
- Attach: `asc versions attach-build --version-id <id> --build <buildId>`.
- Validate: `asc validate --app 6822892688 --version 1.1.0 --platform IOS`.
- Submit: `asc review submissions-submit --id <submissionId> --confirm`.

Gotchas:

- **`dl.google.com` is filtered on Iranian networks.** Every path returns an
  identical 1,449-byte fake 404, so `pod install` fails while downloading
  FirebaseAnalytics (also check with a known-good Maven POM, not just the
  Firebase URL). The Pods sandbox already contains the framework from the last
  successful build: copy `Podfile.lock` to `Pods/Manifest.lock`, run
  `LANG=en_US.UTF-8 pod install`, and CocoaPods reuses the sandbox instead of
  downloading. Confirm with `Pod installation complete!`; never delete `Pods/`
  on this network.
- TestFlight internal groups cannot be assigned a build
  (`Builds cannot be assigned to this internal group`). Internal testers with
  access to all builds see a valid build automatically.
- `asc builds test-notes create` fails with *"There is an entity with same
  'locale'"* when a note already exists for that build; use `test-notes update`.
- A version in `READY_FOR_REVIEW` is not editable. Preview uploads and build
  changes fail with *"Can't Create Preview Set while Ready For Review"*.
  Remove the item from the submission
  (`asc review items-remove --id <item> --confirm`). The version moves to
  `DEVELOPER_REJECTED`, which is editable, and the existing submission can be
  reused by adding the item back.
- `asc review items-update --state` is rejected by the current API ("attribute
  'state' can not be included in a UPDATE operation"); use `items-remove`.
- Preview upload answers COMPLETE for the upload, not Apple's processing
  verdict. Re-read `asc video-previews list` a few minutes later before
  submitting; a failed preview blocks the submission and must be deleted.
- `whatsNew` cannot be set on a never-released app. Validation reports it as
  a warning, not a blocker.
- The brag video (`1080x1920`, 20 s, H.264/AAC) fits the `IPHONE_55` preview
  slot. Play has no file upload for promo video, only a YouTube URL.

## Support and premium configuration

Both are build-time values; neither is committed.

- **Support.** `SUPPORT_URL` (`.env` or `--dart-define=SUPPORT_URL=…`) must be
  the **public** Teleform form or its Telegram hand-off. The Teleform
  dashboard at `app.teleform.io/dashboard` is login-gated and must never be
  linked in the app. With the key empty the Support row is not rendered — that
  is the correct shipping state until a public link exists.
- **Premium.** `REVENUECAT_APPLE_KEY` and `REVENUECAT_GOOGLE_KEY` configure the
  RevenueCat SDK per platform (entitlement `premium`). A missing key leaves
  that platform `PremiumStatus.unconfigured`: the paywall says store setup is
  not live instead of showing a price. As of build 19 the Apple key is present
  and the Google key is not, so Android premium cannot be purchased until the
  key is supplied and a new build is uploaded.
- Verify before upload: support link opens on a device without a login wall;
  iOS paywall loads products; Android paywall shows the unconfigured notice
  rather than a fake price.

## Ads enablement

1. Confirm live AdMob IDs and set `useTestAds = false` in
   `lib/modules/monetization/ad_config.dart`.
2. Replace the test application IDs in `AndroidManifest.xml` and
   `ios/Runner/Info.plist`.
3. Ship a release with those IDs.
4. Flip `ads_enabled = true` in Firebase Remote Config. The app reads the
   last activated value on launch; failures and offline first launches stay
   off.

## Screenshots and site imagery

- Capture on a debug build: `ScreenSecurity` returns early in `kDebugMode`,
  so `adb exec-out screencap` is not black while connected. Release builds
  keep FLAG_SECURE. The debug console icon is debug-only and safe to show.
- Device captures must be 1080x2400. Run the generator with those files:

  ```bash
  python3 scripts/make_store_screenshots.py \
    --home /tmp/shot_home_connected.png \
    --connecting /tmp/shot_connecting.png \
    --servers /tmp/shot_servers4.png \
    --speed-running /tmp/shot_speed_running.png \
    --speed-result /tmp/shot_speed_fixed.png
  ```

  It writes `store/screenshots/play-phone` (1080x1920 JPEG),
  `store/screenshots/iphone69` (1290x2796 PNG), `assets/onboarding`
  (720x1600 JPEG), and the site webp files.
- `firebase.json` serves images with `max-age=31536000, immutable`. Never
  replace a screenshot in place on the site: bump the `-v2` suffix and update
  the HTML references, or returning visitors keep the old bytes for a year.
- `site` deploys with `firebase deploy --only hosting --project bulbvpn-e9b4c`.
