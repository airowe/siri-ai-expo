# Proposal for expo-app-intents: Siri AI Developer Preview support

A draft feature request for [expo.canny.io/feature-requests](https://expo.canny.io/feature-requests). Expo asks people to write their own issues ("Edit an agent's draft down to the facts before you post it"), so edit the post below into your own words before submitting. Every number comes from [SPIKE.md](../SPIKE.md).

## Before posting

- [x] Make the repo public so the post can link to a reproduction: https://github.com/airowe/siri-ai-expo
- [x] Search Canny for an existing request. Nothing covers Siri AI, App Intents or Apple Intelligence (checked Nov 10, 2026). The only related post is an old "Siri Shortcuts" request about `NSUserActivityTypes`.
- [ ] Check whether `runBackgroundTask` ([expo/expo#51595](https://github.com/expo/expo/pull/51595), merged Oct 27) has shipped in a release newer than 0.5.16. If it has, mention it and drop anything it covers.

Canny takes raw Markdown with no preview: headings, bold, italic, lists, links, inline code and fenced code blocks. Tables aren't supported, so the post uses lists. Blank lines inside a code block collapse unless the line holds a space.

---

## Post

**Title:** Siri AI Developer Preview: setup and guidance for tools in expo-app-intents

**Body** (copy everything between the lines):

---

I tested Apple's Siri AI Developer Preview (iOS 27.3 beta) with expo-app-intents 0.5.16 on Expo SDK 58, on a real iPhone. **The package works unchanged.** Siri called tools written in `app-intents/`, including with the app closed and with the phone locked. A few preview-specific pieces needed workarounds, and I'd like to know whether you'd welcome contributions for them.

Reproduction and write-up: https://github.com/airowe/siri-ai-expo

**Setup:** Xcode 27.3 beta (27C5020n), iPhone 16 Pro on iOS 27.3 beta (24C5037i) with Siri AI on, Release build signed for development.

### What worked with no package changes

- `@AppIntent(.tool)` intents in `app-intents/`. Siri called them and spoke their dialog, with the app open, with it closed, and with the phone locked.
- `@AppEntity(.generable)` parameters filled in by Siri.
- Entities published from JavaScript with `setEntityCatalogAsync` and `reindexEntitiesAsync`, found by Siri through Spotlight.
- A tool that calls an authenticated API and refreshes an expired token inside the Siri request.

### Where I needed workarounds

1. **Compiling the tool code.** The tool macros only exist in the 27.3 SDK. I gated them behind a Swift compilation condition set by my own config plugin:

   ```js
   entry.buildSettings.SWIFT_ACTIVE_COMPILATION_CONDITIONS = `"$(inherited) SIRI_AI_PREVIEW"`;
   ```

2. **Deployment target.** `@Property(title:description:)` is iOS 27.3+ only, and a property wrapper can't be limited to newer versions with an availability check. Any entity that uses it raises the whole app to iOS 27.3.
3. **Prebuild.** `expo prebuild` regenerates `ios/`, so I need a script to re-add the Siri Evaluations test target after every prebuild. A Skills Bundle added in Xcode is presumably lost the same way (not yet verified).
4. **Siri answers from indexed data instead of calling the tool.** This is the one I'd most like to see in the docs:
   - With order status in the entity and its Spotlight description, Siri called the status tool in **3 of 8** runs. In the rest it gave the same facts in its own words, from the index.
   - With only the order's identity indexed (id, name, synonyms) and the tool reading status when it runs: **4 of 4** completed runs.
   - A tool with nothing indexed (a cart fetched from an API): **5 of 5**.
   - The rule: index what identifies a record, never the answer the tool exists to give.
5. **Locked phone.** Tools that read a token need Keychain items readable after first unlock (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). With that, Siri read an authenticated result with the phone locked.
6. **Testing.** Xcode 27.3 ships `SiriEvaluations.framework` for devices only, not for the Simulator.

### Question

Would you welcome contributions for any of these, or would you rather wait until the APIs leave beta?

- A config plugin option that sets the preview compilation condition and keeps the Siri Evaluations target and Skills Bundle through prebuild.
- A tool example for `npx expo-app-intents init`.
- Guidance in the docs and the bundled agent skill, covering points 4 and 5.

I'm also following `runBackgroundTask` (#51595), which covers tools answering from JavaScript, so I've left that out.

---

## If they accept: what each pull request needs

From Expo's CONTRIBUTING.md and AGENTS.md. Read AGENTS.md before editing anything in expo/expo.

- **One change per pull request**, linked to the accepted request, with a changeset (`pnpm changeset`, `minor` for a new option).
- **Tests that fail before the change and pass after it.** No tests that already pass, and none that only check a mock.
  - Config plugin option: plugin unit tests that compile a fixture project and check the build setting and the kept targets, with the flag both off and on.
  - Native changes: Swift tests in `ExpoAppIntents-Unit-Tests`, following the `runBackgroundTask` PR.
  - Tool example: building it in CI is the test, because Siri can't run in CI.
- **A test plan you ran.** Name the device and OS. Include Siri Evaluations output from a real device, and a negative control showing the check can fail.
- **AI disclosure.** One line in `How` saying which tool was used and for what. No co-author trailers in commits.
- **Authorship.** You must be able to explain every line in review without the tool. Open pull requests yourself and keep only a few open at once.
