# Proposal for expo-app-intents: Siri AI Developer Preview support

Notes for a feature request on [expo.canny.io](https://expo.canny.io). Expo closes feature requests opened as GitHub issues, and asks that issues be written by the person posting them: "Edit an agent's draft down to the facts before you post it." Rewrite this in your own words before posting. Every number below comes from `SPIKE.md`.

## Before posting

- [ ] Make the spike repo public, so the post can link to a reproduction. Expo weighs a real repro above a description.
- [ ] Check that `runBackgroundTask` ([expo/expo#51595](https://github.com/expo/expo/pull/51595), merged Oct 27, not in 0.5.16) hasn't shipped with Siri AI support in the meantime.
- [ ] Search Canny for an existing Siri AI request and vote or comment there instead of opening a duplicate.

## Facts for the post

**Setup.**
- expo-app-intents 0.5.16 on Expo SDK 58.
- Xcode 27.3 beta 27C5020n.
- iPhone 16 Pro on iOS 27.3 beta 24C5037i with Siri AI on.
- Release build signed for development.

**What worked with no change to the package:**
- `@AppIntent(.tool)` on intents in `app-intents/`. Siri called them with the app closed and with the phone locked.
- `@AppEntity(.generable)` parameters.
- Entities published from JavaScript with `setEntityCatalogAsync` and `reindexEntitiesAsync`. Siri found them in the Spotlight index on the device.
- Tools that answer from Swift, including one that calls an authenticated API and refreshes an expired token.

**Where I needed workarounds:**

1. **The tool code only compiles with the iOS 27.3 SDK.** I gated it behind a Swift compilation condition set by my own config plugin (`SWIFT_ACTIVE_COMPILATION_CONDITIONS += SIRI_AI_PREVIEW`).
2. **`@Property(title:description:)` is iOS 27.3+ only, and a property wrapper can't be limited to newer versions with an availability check.** Any entity that uses it raises the whole app's deployment target to 27.3.
3. **`expo prebuild` regenerates `ios/`, so anything added in Xcode has to be redone.** I needed a Ruby script to re-add the Siri Evaluations test target after each prebuild. Not yet verified: whether a Skills Bundle is also removed (check 8 in the spike).
4. **Siri often answered from indexed data instead of calling the tool.**
   - With order status and arrival stored in the entity and its Spotlight description, Siri called the status tool in 3 of 8 runs. In the other runs it gave the right facts in its own words.
   - After I indexed only the order's identity (id, item name, synonyms) and had the tool read status when it runs, Siri called it in 4 of 4 completed runs.
   - A tool with nothing indexed (a cart fetched from an API) was called in 5 of 5.
   - Lesson: index what identifies a record, never the answer the tool exists to give.
5. **Tools that run while the phone is locked need Keychain items readable after first unlock** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Siri read an authenticated result with the phone locked.
6. **Siri Evaluations only runs on a device.** Xcode 27.3 ships `SiriEvaluations.framework` for devices only, not for any Simulator SDK.

**Question for the Expo team:** expo-app-intents already works with the Siri AI preview once you write the tool Swift yourself. Would you welcome contributions that cover the preview-specific setup, examples and guidance, or would you rather wait until the APIs are out of beta?
- A config plugin option that sets the preview compilation condition and keeps the Siri Evaluations target and Skills Bundle through prebuild.
- A tool example for `npx expo-app-intents init`.
- Guidance in the bundled skill and the docs, covering points 4 and 5.

## If they accept: what each pull request needs

These come from Expo's CONTRIBUTING.md and AGENTS.md. Read AGENTS.md before editing anything in expo/expo.

- **One change per pull request**, linked to the accepted issue, with a changeset (`pnpm changeset`, `minor` for a new option).
- **Tests that fail before the change and pass after it.** Don't add tests that already pass, or tests that only check a mock.
  - Config plugin option: plugin unit tests that compile a fixture project and check the build setting and the preserved targets, in both the flag-off and flag-on cases.
  - Native changes: Swift tests in `ExpoAppIntents-Unit-Tests`. The `runBackgroundTask` PR is the model to follow.
  - Tool example: building it in CI is the test. Siri behaviour can't run in CI.
- **A test plan you ran.** Name the device and OS. Include Siri Evaluations output from a real device, and a negative control showing the check can fail.
- **AI disclosure.** One line in `How` saying which tool was used and for what. No co-author trailers in commits.
- **Authorship.** You must be able to explain every line in review without the tool. Open pull requests yourself and keep only a few open at once.
