# Store readiness checklist

Status legend: [x] done in repo, [ ] needs you.

- [x] No network code (CI guard) — simplifies data-safety declarations: "no data collected, no data shared".
- [x] Draft privacy policy: `docs/PRIVACY_POLICY.md` — [ ] host it at a public URL and review it.
- [x] Android listing text: `fastlane/metadata/android/en-US/`.
- [ ] App icon, adaptive icon, splash (generate with a tool of your choice; none are included).
- [ ] Screenshots (phone, 7"/10" tablet; iPhone 6.7"/6.5", iPad if supported).
- [ ] **Play: All files access** (`MANAGE_EXTERNAL_STORAGE`) requires a permission declaration. Prepare the justification (user-chosen vault folder, Obsidian-style) or switch to the SAF-only picker and drop the permission.
- [ ] Play: content rating questionnaire, target audience, data safety form, signing enrolment.
- [ ] iOS: App Privacy ("Data Not Collected"), age rating, export-compliance answer (no encryption beyond OS), review notes explaining the folder picker.
- [ ] iOS: confirm file-sharing keys (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`) were patched in `Info.plist`.
- [ ] Set real bundle id / application id, version, and a license (`LICENSE`).
- [ ] Run `flutter analyze`, `flutter test`, and manual tests on real Android and iOS devices (folder picking, resume rescan, large vaults).
