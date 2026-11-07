# Siri AI spike

Does `expo-app-intents` 0.5.16 (Expo SDK 58) work with the Siri AI Developer Preview without changes to the package?

## Results so far (Xcode 27.2, iOS 27.2 Simulator, flag off)

| Check | Result |
|---|---|
| Intent, entity and query extracted from the inline module into `Metadata.appintents` | Pass |
| Debug and Release simulator builds | Pass |
| Deployment target stays 16.4 | Pass, flag off only |
| Flag reaches inline module (negative check: flag on fails only on the 27.3 APIs) | Pass |
| Orders stored and read back from the native catalog | Pass |
| Spotlight indexing | **Unresolved on the simulator**, see below |
| Non-clean `expo prebuild` regenerates `ios/` and drops manual project edits | Confirmed: flag removed, Pods and workspace removed |

## Results with Siri AI on (Xcode 27.3 beta 27C5020n, iOS 27.3 Simulator)

| Check | Result |
|---|---|
| Builds with the flag on (check 1) | **Pass, but only with the deployment target raised to 27.3** |
| `GetOrderStatusIntent`, `SearchOrdersIntent`, `OrderEntity` and `OrderSearch` in `Metadata.appintents` | Pass. The extracted file has no field that marks an intent as a tool, so this doesn't confirm the tool trait |
| Deployment target stays 16.4 | **Fail.** `@Property(title:description:)` is available only on iOS 27.3 or later, and a property wrapper can't be marked available on newer versions only. Any entity that uses it raises the whole app to 27.3 |
| Siri evaluation compiles for a device | Pass (`generic/platform=iOS`, unsigned) |
| Siri evaluation runs in the Simulator | **No.** Xcode 27.3 ships `SiriEvaluations.framework` only for iOS, macOS and visionOS devices, not for any Simulator SDK. `Evaluations` and `AppIntentsTesting` do ship for the Simulator |

`SearchOrdersIntent` needed one fix: a computed `displayRepresentation` must return `DisplayRepresentation(title:)`, not a string literal.

### Spotlight on the simulator

On a clean install, `setEntityCatalogAsync` and `reindexEntitiesAsync` both failed to return within 20 seconds. The system log shows Core Spotlight failing with `CSIndexErrorDomain -1000`, because its connection to `com.apple.SetStoreUpdateService` was invalidated. The package's stale-index flag stayed `true`. One rerun with the orders already stored reported `ok` for every step, so `ok` alone doesn't prove the index was written.

This may be simulator-only, but that hasn't been tested. Check 2 below settles it.

## Prerequisites

- Xcode 27.3 beta, confirmed. Xcode 27.2 has no `ToolIntent`, `GenerableEntity` or `@Property(description:)`.
- An Apple Intelligence iPhone on iOS 27.3 beta, in a supported language, with Siri AI turned on. Siri AI isn't available on iPhone in the EU.
- Skills can't be tested in the Simulator.

## Build with Siri AI on

```bash
sudo xcode-select -s /Applications/Xcode-beta.app
```

Use your Xcode beta's actual path in that command.

```bash
SIRI_AI_PREVIEW=1 CI=1 npx expo prebuild -p ios
```

If `pod install` fails because `hermesvm.xcframework/Info.plist` doesn't exist, the cached Hermes pod is missing that file. Run it with an empty cache:

```bash
cd ios && CP_CACHE_DIR="$PWD/../.cp-cache" LANG=en_US.UTF-8 pod install
```

Add the Siri evaluation target. Prebuild removes it, so run this again after each prebuild:

```bash
ruby scripts/add-siri-eval-target.rb
```

```bash
open ios/SiriSpike.xcworkspace
```

In Xcode:

1. Under Signing & Capabilities, choose your team for both `SiriSpike` and `SiriSpikeSiriEvals`. Change the bundle IDs if they're taken. Set the deployment target of `SiriSpike` to 27.3.
2. Choose File > New > File from Template > Skills Bundle. Keep the name `Skills` and select the `SiriSpike` target.
3. Create `order-tracking/SKILL.md` inside the bundle's `Skills` folder, using the contents of `skills/Skills.skillsbundle/Skills/order-tracking/SKILL.md`.
4. Choose the Release configuration so the app runs without Metro, then run on your iPhone.
5. Keep the app open until all three status lines finish, and record them. `TIMED OUT` on Publish or Spotlight is a finding, not a reason to stop.

Running prebuild again removes the Skills Bundle from the project, so repeat steps 1–3 afterwards.

## Device checks

Try each request by voice or typed to Siri. Record what happens, including the exact response. Run each request at least twice, because Siri's responses can vary.

| # | Tests | App state | Request | Pass means | Result |
|---|---|---|---|---|---|
| 1 | Build | n/a | Build with the flag on | Compiles, and `SearchOrdersIntent` is in the metadata | |
| 2 | Spotlight index | n/a | Search for "trail running shoes" in Spotlight on the iPhone | The order appears, and Publish and Spotlight don't time out | |
| 2a | Tool, foreground | Open | "Where are my trail running shoes?" | Says out for delivery, today by 6 PM | |
| 3 | Tool, background | Closed | "In Siri Spike, where is my desk lamp?" | Says shipped, on Friday, without opening the app | |
| 4 | Entity search | Closed | "What coffee did I order in Siri Spike?" | Finds Ethiopian coffee beans | |
| 5 | Generable entity | Open | "Search my orders for shoes" | Calls Search Orders with keyword "shoes" | |
| 6 | Skill | Open | "Is my delivery coming?" | Asks which order, rather than guessing | |
| 7 | Control | Closed | "Where's my package?" without naming the app | Doesn't call the tools, per Apple's rules | |
| 8 | Prebuild | n/a | Run prebuild again, then search `project.pbxproj` for `skillsbundle` | No matches, so a plugin is needed | |
| 9 | Older iOS | n/a | Run on a simulator or device below 27.3 | Launches, publishes orders, no tool crash | |

The Siri Integration Advisor in Xcode may also explain failures in checks 2–6. Note what it reports.

## Siri evaluation

`siri-evals/OrderStatusEvaluationTests.swift` automates check 2a. It launches the app, waits until the status shows the Spotlight step, then asks Siri "In Siri Spike, where are my trail running shoes?" It passes when Siri runs `GetOrderStatusIntent` and its reply contains "out for delivery".

To run it on an iPhone, turn on Developer Mode, then Settings > Developer > Enable UI Automation. Choose the `SiriSpikeSiriEvals` scheme, then Product > Test. Apple says to run evaluations more than once, because Siri's responses vary. Xcode shows a report of each turn.

## Not covered

- JavaScript background tasks: `runBackgroundTask` isn't in 0.5.16, so this app answers from Swift.
- Running the Siri evaluation, which needs a device or a Mac on a 27.3 beta.
- Checks 3–7 as evaluations. Check 3 needs the app closed, and the evaluation launches it.
- Automating the skills bundle: that's the next milestone, once check 6 passes.
