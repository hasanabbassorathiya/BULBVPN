# Store release runbook

Operational notes from the 1.1.0 release. Keep this file updated when a tool
behaves differently from its docs.

## Version discipline

- One source of truth for the app build: `pubspec.yaml` (`1.1.0+13`).
- iOS takes the Runner build from `FLUTTER_BUILD_NUMBER`; the PacketTunnel
  extension reads `CURRENT_PROJECT_VERSION` from
  `ios/Runner.xcodeproj/project.pbxproj`. Bump both.
- A build number that reached App Store Connect or Play can never be reused.
  Check both stores before bumping or re-uploading.

## Google Play

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
  can publish normally.
- Read the track back in a fresh edit after committing; the commit response
  itself does not prove the release landed.

## App Store Connect

- App id `6822892688`.
- Upload: `asc builds upload --app 6822892688 --ipa build/ios/ipa/BULBVPN.ipa --wait`.
  The build is VALID minutes after the upload reports committed.
- Attach: `asc versions attach-build --version-id <id> --build <buildId>`.
- Validate: `asc validate --app 6822892688 --version 1.1.0 --platform IOS`.
- Submit: `asc review submissions-submit --id <submissionId> --confirm`.

Gotchas:

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

## Ads enablement

1. Confirm live AdMob IDs and set `useTestAds = false` in
   `lib/modules/monetization/ad_config.dart`.
2. Replace the test application IDs in `AndroidManifest.xml` and
   `ios/Runner/Info.plist`.
3. Ship a release with those IDs.
4. Flip `ads_enabled = true` in Firebase Remote Config. The app reads the
   last activated value on launch; failures and offline first launches stay
   off.
