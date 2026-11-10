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

## Results on a device (iPhone 16 Pro, iOS 27.3 beta 24C5037i, Siri beta on)

Built and tested over Wi‑Fi with `xcodebuild`, Release configuration, `DEVELOPMENT_TEAM` and `IPHONEOS_DEPLOYMENT_TARGET=27.3` passed on the command line.

| Run | Expected reply | Tool called | Siri's reply | Result |
|---|---|---|---|---|
| 1 | contains "out for delivery" | `GetOrderStatusIntent`: yes | "From Siri Spike: Trail running shoes is out for delivery, arriving today by 6 PM." | **Pass** (intents 1/1, response 1/1) |
| 2, negative control | contains "shipped" (wrong on purpose) | `GetOrderStatusIntent`: **no** | "Your trail running shoes are out for delivery and scheduled to arrive today by 6:00 PM." | Fail, as intended (intents 0/1, response 0/1) |

- Run 1 is check 2a. The reply is the tool's dialog, so Siri ran our Swift code. The evaluation's diagnostics show 3 `OrderEntity` items in the Spotlight index, so check 2 passes on device too.
- Run 2 gave the right facts **without calling the tool**. Siri likely answered from the indexed entity data. Whether Siri calls the tool varies from run to run, so a single passing run doesn't prove the tool is reliable.
- The test now asserts `siriResponseAllPass` as well as `intentsAllPass`, so each failure says which part went wrong.

| Run | Expected reply | Tool called | Siri's reply | Result |
|---|---|---|---|---|
| 3 | contains "out for delivery" | **no** | "Your trail running shoes are out for delivery and scheduled to arrive today by 6 PM." | Fail on intents only; response passed |
| 4, negative control | contains "shipped" | no | (same facts) | Fail on intents and on response |

### Full evaluation suite (4 evaluations, 8 Siri requests, about 4 minutes)

| Evaluation | Check | Tool calls | Reply | Result |
|---|---|---|---|---|
| Trail running shoes, once | 2a | `GetOrderStatusIntent`: yes | "From Siri Spike: Trail running shoes is out for delivery, arriving today by 6 PM." | Pass |
| Trail running shoes, 5 times | 2a | Called in 1 of 5. One run ended before its results arrived | All 5 had the right facts. Only the run that called the tool began "From Siri Spike" | Fail: intents 0.2, response 0.8 (the incomplete run counts as a fail) |
| "Search my Siri Spike orders for shoes" | 5 | `SearchOrdersIntent`: yes | "I found one order for trail running shoes, which is out for delivery and expected today by 6 PM" | Pass |
| "Where's my package?" | 7 | Neither tool called | "Which package? The trail running shoes, the brass desk lamp, or the Ethiopian coffee beans?" | Pass |

Findings:

- **The status tool is called in about 3 of 8 runs** (all runs of the status question with the correct expected reply, on this device). The other replies have the same facts in Siri's own words. Those facts can only have come from the indexed `OrderEntity` data, so Siri is answering from the Spotlight index instead of running the tool. For an app whose answers must be live (an API call, an expired token), that would be wrong. Unknowns: whether Siri does this with the app closed, and whether indexing fewer properties would push Siri to call the tool.
- **The search tool and the generable `OrderSearch` entity work.** Siri called `SearchOrdersIntent` with a keyword and summarized the returned entities. The evaluation didn't check the keyword's value.
- **The control passed but leaked app data.** Without the app being named, Siri didn't call a tool, but it listed all three orders by name. The data came from the Spotlight index, so the rule "don't call tools unless the app is named" doesn't stop Siri from using indexed data.
### Status and arrival removed from the entity and the index

`OrderEntity` now holds only `id`, `item` and `synonyms`. Status and arrival are no longer entity properties, in the display subtitle, or in the Spotlight `contentDescription`. `GetOrderStatusIntent` reads them from the entity store when it runs, the way a live API call would.

| Evaluation | Completed runs | Tool called | Reply |
|---|---|---|---|
| Status, once | 0 of 1 (ended before results arrived) | n/a | none |
| Status, 5 times | 4 of 5 | **4 of 4** | "From Siri Spike: Trail running shoes is out for delivery, arriving today by 6 PM." each time |
| Search for shoes | 0 of 1 (ended before results arrived) | n/a | "I found one order for trail running shoes" |
| "Where's my package?" | 1 of 1 | Neither, as required | Still lists the three orders by item name |

- **Indexing only identity makes Siri call the tool.** Of the status runs that completed, Siri called the tool in 4 of 4, against 3 of 8 when status and arrival were indexed. Rule for the tool and its guide: index what identifies a record, never the data the tool exists to answer.
- **3 of 8 runs ended before all their results arrived.** The evaluation scores those as failures, so the suite fails even when Siri behaved correctly. The cause isn't known yet. It may be the first request after a fresh install, or a timeout in the evaluation.
- Item names are still indexed, so Siri can still list orders without the app being named. That's by design for entity search, but it means indexed titles shouldn't contain anything private.

### Tool that calls a demo API

`GetCartIntent` fetches `https://dummyjson.com/carts/1` with `URLSession` (10-second timeout) and reads the cart back. If the request fails, it says "Couldn't reach the cart service." rather than throwing. Nothing about the cart is indexed, so a reply that names its products can only come from the API. The order tools are unchanged.

| Run | Expected reply | Tool called | Siri's reply | Result |
|---|---|---|---|---|
| 5 times | contains "motorcycle" | `GetCartIntent`: **5 of 5** | "From Siri Spike: Your cart has 4 products, $13,037.88: Blue Frock, Generic Motorcycle, iPhone 6, Baseball Ball." each time | **Pass** (intents 1, response 1) |
| 5 times, negative control | contains "laptop" (wrong on purpose) | 4 of 5; run 1 ended before its results arrived | Same reply each time | Fail, as intended (intents 0.8, response 0) |

- **Siri calls a live API tool every time when there is no indexed data to answer from.** That fits the identity-only indexing rule above.
- The incomplete-run problem showed up again (run 1 of the control) even though Siri gave the full reply, so it looks like a problem in the evaluation harness rather than in Siri or the tool.
- **By hand with the app closed: pass.** "In Siri Spike, what's in my cart?" got the correct cart without the app opening (exact reply not recorded). A Swift tool can make a live HTTPS call while the app isn't running.

### Authenticated call with an expired token

When the app opens, Swift logs in to DummyJSON's public demo account (`emilys`) with a **one-minute** access token and saves both tokens in the Keychain (`AfterFirstUnlockThisDeviceOnly`). `GetCartIntent` now calls the protected `/auth/carts/1`. On a 401 or 403 it refreshes once, saves the new tokens and retries. If that fails, it replies "Open Siri Spike to sign in again." The tool records what it did, and the app shows that on screen, so a test can tell a refresh from a token that was still valid. Real Expo apps sign in from JavaScript; reading a token that JavaScript saved is a later step.

Each evaluation run signs in, waits 70 seconds, then asks "In Siri Spike, what's in my cart?"

| Evaluation | Tool outcome recorded | Siri's reply | Result |
|---|---|---|---|
| Refresh on, 5 runs | "refreshed after 401", about 78 s after each sign-in | Full cart, 5 of 5 | 3 of 5 scored; runs 2 and 5 ended before their results arrived |
| Refresh off (negative control), 5 runs | "signed out", about 80 s after each sign-in | "From Siri Spike: Open Siri Spike to sign in again.", 5 of 5 | Fail, as intended (response 0) |
| Fresh token, no wait, 5 runs | not printed by this evaluation | Full cart, 5 of 5 | 2 of 5 scored; 3 ended before their results arrived |

- **An expired token is refreshed inside a Siri tool call.** DummyJSON returns **401** for an expired access token, which the docs don't say. The refresh and retry fit inside Siri's wait.
- **The negative control shows the check can fail:** with refresh off, every reply told the person to sign in again.
- **The incomplete runs are in the evaluation harness, not in Siri or the tool.** In run 2 of the refresh evaluation, the tool recorded a refresh at 11:35:48 and Siri gave the full reply, yet the run was scored "ended before all of its results arrived". The rate was highest (3 of 5) while Siri was also hearing a person nearby.
By hand (results reported as passing; exact replies not recorded):

| Check | Pass means | Result |
|---|---|---|
| Fresh token | App shows "used saved token" | Pass |
| Expired token, app closed | Cart read without opening the app; app shows "refreshed after 401" | Pass |
| Signed out | "Open Siri Spike to sign in again." | Pass |
| Phone locked, token expired | No fixed expectation; recording what happens | **Siri read the cart without asking to unlock** |

- **A tool can use saved tokens while the phone is locked**, as long as the Keychain item is readable after the first unlock (`AfterFirstUnlockThisDeviceOnly`). A token stored with stricter protection (`WhenUnlocked`, which some secure-storage libraries use by default) would likely fail here. That's worth checking when Swift reads a token saved from JavaScript.

- The first refresh run printed each outcome one run late, because the app read it only at launch. The app now re-reads it every second; the control run shows the fix working.

- Connection: over Wi‑Fi, the run fails with "Lost pending connection to the test runner" if the phone locks. Set Auto-Lock to Never while testing.

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
| 3 | Tool, background | Closed | "In Siri Spike, where is my desk lamp?" | Says shipped, on Friday, without opening the app | **Pass** (by hand, after the identity-only entity change; exact reply not recorded). Milestone 1 met |
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
- Checks 3, 4 and 6 as evaluations. Checks 5 and 7 are automated. Check 3 needs the app closed, and the evaluation launches it.
- Automating the skills bundle: that's the next milestone, once check 6 passes.
