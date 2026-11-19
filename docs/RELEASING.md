# Releasing

Nothing here is automated end-to-end until you add credentials. Without them, workflows produce unsigned artifacts only.

## Android
1. Create an upload keystore (keep it out of git): `keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Local builds: create `android/key.properties` (git-ignored) with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`; run `tool/bootstrap.sh --signing`.
3. CI secrets: `ANDROID_KEYSTORE_BASE64` (`base64 -w0 upload.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
4. Play upload: secret `PLAY_SERVICE_ACCOUNT_JSON` (service account with release permission). The first release of a new app must be uploaded manually in Play Console.
5. Fastlane: `bundle exec fastlane android internal`.

## iOS
1. Apple Developer account, bundle id matching `PF_ORG` used at bootstrap (default `com.promptforge.promptForge`).
2. Secrets: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_BASE64` (App Store Connect API key), and for code signing `MATCH_GIT_URL`, `MATCH_PASSWORD`.
3. Fastlane: `bundle exec fastlane ios beta` (TestFlight).

## Cutting a release
1. Bump `version:` in `pubspec.yaml`; fill in `RELEASE_NOTES_TEMPLATE.md`.
2. Tag `vX.Y.Z` and push; `release.yml` builds, signs when secrets exist, and creates the GitHub release (pre-release if unsigned).
3. Lanes refuse to run without credentials; they never pretend to publish.
