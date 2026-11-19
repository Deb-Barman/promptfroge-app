# Prompt Forge (Flutter)

An offline, local-first prompt workspace for Android and iOS, ported from the single-file `PromptForge.html` app.
Your prompts live as **plain Markdown files in a folder you pick or create** (the Obsidian model). There is no AI,
no backend, no account, no sync and no network code.

## Build the Android APK with GitHub Actions (no computer needed)

1. Create a GitHub repository and upload **everything in this zip** (keep the `.github` folder; it is hidden on some systems).
2. Open the repo's **Actions** tab, choose **Android build**, press **Run workflow**. (It also runs on every push to `main`.)
3. After about 10-15 minutes open the finished run, scroll to **Artifacts**, download **PromptForge-android-apk**, unzip it.
4. Copy `PromptForge-1.0.0-arm64-v8a.apk` to your phone (most phones from the last ~8 years) or the `-universal.apk` (works on any
   Android phone, bigger file), open it, and allow "Install unknown apps" when asked.
5. Open the app, choose **Create a new vault** (or **Open an existing folder**, e.g. an Obsidian vault) and grant *All files access*.

No keystore or secrets are needed: the APK is signed with Flutter's debug key, which is fine for your own phone. A Play Store
release needs a real keystore (see [docs/RELEASING.md](docs/RELEASING.md)).

**iPhone:** the **iOS build** workflow compiles the app on a macOS runner and produces an **unsigned** `.app`. Apple does not let
you install unsigned apps on a normal iPhone. To run it you need either an Apple Developer account (TestFlight, see
[docs/RELEASING.md](docs/RELEASING.md)) or a sideloading tool such as AltStore/Sideloadly, which re-signs it with your Apple ID.
There is no way around this on iOS.

## What has and has not been verified

Verified (by running real tooling, not by reading):

- **Static analysis:** the whole `lib/` analyzes with **0 errors and 0 warnings** against the real Flutter **3.50.0** framework
  sources, Riverpod 2.6.1 and go_router 14.8.1. The five platform plugins (file_picker, permission_handler, path_provider,
  shared_preferences, share_plus) were checked against small hand-written API stubs, so their exact signatures are still
  confirmed only by the real build.
- **Engine parity:** 338 headless Dart tests pass, including golden tests that compare the Dart engines (analyzer, templates,
  cleaner, scanners, converters, diff, search, exact GPT tokenizer, graph layout, date parser) with the output of your **original
  JavaScript** run in node, plus vault read/write and settings round-trips.

Not verified (please expect to fix small things on the first real run):

- No APK/IPA has been built and the app has never been launched on a device or emulator.
- The widget tests (`test/widget`, `test/vault/notifier_test.dart`) and the GitHub workflows have not been executed.
- Folder picking / All-files permission and the file-sharing plugins need a real phone to confirm.

## Vault format

```
MyVault/
  Prompts/<title>.md       frontmatter (JSON values) + prompt body; [[wiki links]] work
  Templates/  Patterns/  Snippets/  Chains/
  Exports/                 files produced by the export tools
  .promptforge/            settings, groups, saved searches, builder structures, version history
```

Files are written atomically (temp file, then rename). The app rescans on resume and on pull-to-refresh, and an open
prompt that changes on disk shows a conflict banner instead of being overwritten. You can edit the files in any editor.

## Setup

1. Install Flutter **3.50.0** (the version the CI is pinned to and the code was analyzed against).
2. `tool/bootstrap.sh` — generates `android/` and `ios/`, removes the sample test, patches permissions/file sharing
   (`tool/patch_platforms.py`), runs `flutter pub get`. Commit the generated folders afterwards.
   Add `--signing` to wire Android release signing (see [docs/RELEASING.md](docs/RELEASING.md)).
3. `flutter analyze && flutter test && flutter run`

## Generated files

- `lib/core/constants_data.dart` is generated from `reference/PromptForge.html`:
  `node tool/gen_constants.js reference/PromptForge.html > lib/core/constants_data.dart`
- `test/goldens/engines.json` is produced by running the **original JavaScript** engines in node:
  `node tool/golden/gen_goldens.js`. Never hand-edit it. See [tool/golden/README.md](tool/golden/README.md).

CI fails if either file is out of date.

## CI / release

`.github/workflows`: `ci.yml` (analyze + test, generated-files-current, no-network guard), `android-build.yml`,
`ios-build.yml`, `release.yml`. Signing, Play and TestFlight steps run only when their secrets exist; otherwise the
build is unsigned and the GitHub release is marked pre-release. Nothing is published without credentials.

## Platform caveats

- **Android:** a vault outside app storage needs All-files access (`MANAGE_EXTERNAL_STORAGE`); the app asks. This permission
  needs Play Store justification — see [docs/STORE_CHECKLIST.md](docs/STORE_CHECKLIST.md).
- **iOS:** the picked folder's access may need re-picking after a reinstall; the default vault is in the app's Documents
  folder, visible in the Files app.

## Layout

`lib/core` constants/util/date parsing ·  `lib/domain` models + pure engines · `lib/data/vault` file-system vault ·
`lib/state` Riverpod notifiers · `lib/ui` screens/widgets · `lib/app` router/shell · `docs/` · `tool/` · `fastlane/`.
