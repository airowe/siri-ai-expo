# Siri AI tools in an Expo app

A working Expo app whose tools Siri calls, and what it took to make Siri call them reliably. This uses Apple's Siri AI Developer Preview (iOS 27.3 beta) and [`expo-app-intents`](https://docs.expo.dev/versions/latest/sdk/app-intents).

Everything here was tested on a real iPhone. The raw results, including the runs that failed, are in [SPIKE.md](SPIKE.md).

## What works today

Tested with Expo SDK 58, expo-app-intents 0.5.16, and Xcode 27.3 beta (27C5020n), on an iPhone 16 Pro running iOS 27.3 beta (24C5037i) with Siri AI on.

| What | Result |
|---|---|
| Siri calls a tool and reads its reply, app open | ✅ |
| The same with the app closed | ✅ (by hand) |
| A tool that calls a live API | ✅ 5 of 5 evaluation runs |
| A tool that calls an authenticated API and refreshes an expired token | ✅ (refreshed in every run whose outcome was recorded) |
| The same with the phone locked | ✅ (by hand) |
| A tool whose parameter Siri fills in from the request (`@AppEntity(.generable)`) | ✅ |
| Siri finding entities synced from JavaScript into Spotlight | ✅ |
| Automated Siri tests (Siri Evaluations) | ✅ on a device only |
| expo-app-intents changes needed | None |

**Limits of the preview:**
- The preview needs an Apple Intelligence device, a supported language, and a development-signed build or an internal TestFlight build.
- It isn't available to external TestFlight testers or App Store users. Apple says App Store submission opens in the spring.
- Siri AI isn't available in the EU on iPhone, or for users under 13.
- Apple notes the APIs may change during the preview.

## How it fits together

expo-app-intents compiles your own Swift from `app-intents/` into the app target, where Apple's tools can find it. It also syncs records you publish from JavaScript into native storage and Spotlight.

Siri AI tools are ordinary App Intents with one extra macro, `@AppIntent(.tool)`. The tool's `perform()` runs in Swift and returns the reply Siri speaks. In 0.5.16, JavaScript can receive an intent but can't answer it, so **tools that answer Siri are written in Swift**. Expo has merged [`runBackgroundTask`](https://github.com/expo/expo/pull/51595), which lets JavaScript answer, but it hasn't been released yet.

| File | What it shows |
|---|---|
| [`app-intents/GetOrderStatusIntent.swift`](app-intents/GetOrderStatusIntent.swift) | A tool that answers from data the app stored |
| [`app-intents/Entities/OrderEntity.swift`](app-intents/Entities/OrderEntity.swift) | An entity that holds identity only |
| [`app-intents/SearchOrdersIntent.swift`](app-intents/SearchOrdersIntent.swift) | A tool whose parameter Siri fills in from the request |
| [`app-intents/GetCartIntent.swift`](app-intents/GetCartIntent.swift) | A tool that calls an authenticated API |
| [`app-intents/AuthService.swift`](app-intents/AuthService.swift) | Sign-in, Keychain storage and token refresh |
| [`plugins/withSiriAIPreview.js`](plugins/withSiriAIPreview.js) | Config plugin that turns on the preview code |
| [`siri-evals/OrderStatusEvaluationTests.swift`](siri-evals/OrderStatusEvaluationTests.swift) | Siri Evaluations tests |

## Setup

You need Xcode 27.3 beta (Xcode 27.2 has no tool APIs), and an iPhone on iOS 27.3 beta with Siri AI on, Developer Mode on, and Settings > Developer > Enable UI Automation on.

1. Change the bundle identifier in `app.json`, `siri-evals/OrderStatusEvaluationTests.swift` and `scripts/add-siri-eval-target.rb` to one you own.
2. Point the command-line tools at the beta:

   ```bash
   sudo xcode-select -s /Applications/Xcode-beta.app
   ```

3. Prebuild with the preview flag on:

   ```bash
   SIRI_AI_PREVIEW=1 CI=1 npx expo prebuild -p ios
   ```

4. Add the Siri Evaluations test target. Prebuild removes it, so run this after every prebuild:

   ```bash
   ruby scripts/add-siri-eval-target.rb
   ```

5. Open `ios/SiriSpike.xcworkspace`, choose your team for both targets, set the app's deployment target to 27.3, and run the **Release** configuration on your iPhone, so the app doesn't need a Metro server.

When the app opens, it publishes three orders to Spotlight and signs in to the demo API. Wait for both status lines before trying Siri.

### Why the flag and the 27.3 deployment target

- **The flag:** the tool macros only exist in the 27.3 SDK. [`withSiriAIPreview`](plugins/withSiriAIPreview.js) adds a Swift compilation condition, `SIRI_AI_PREVIEW`, when you prebuild with `SIRI_AI_PREVIEW=1`, so the same code still builds with the stable SDK.
- **The deployment target:** `@Property(title:description:)`, which gives Siri a description of an entity property, is only available on iOS 27.3. A property wrapper can't be limited to newer iOS versions with an availability check, so **any entity that uses it raises the whole app to iOS 27.3**. Leave out the description if you need to support older versions.

## Your first tool

```swift
#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct GetOrderStatusIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Order Status"
  static let description = IntentDescription(
    "Tells the person where one of their orders is and when it should arrive."
  )

  @Parameter(title: "Order", description: "The order the person is asking about.")
  var order: OrderEntity

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let record = try await AppIntentEntityStore.shared.entities(ofKind: "order", matching: [order.id]).first
    let status = record?.metadata["status"] ?? "unknown"
    let arrival = record?.metadata["arrival"] ?? "unknown"
    let answer = "\(order.item) is \(status), arriving \(arrival)."
    return .result(value: answer, dialog: "\(answer)")
  }
}
```

Ask: "In Siri Spike, where are my trail running shoes?" Siri replies with the tool's dialog, prefixed by the app name: "From Siri Spike: Trail running shoes is out for delivery, arriving today by 6 PM."

Apple's documentation says that while the app is in the background, **requests must name the app**. In our test, "Where's my package?" called no tool.

## The indexing rule

> Index what identifies a record. Never index the answer the tool exists to give.

Apple's documentation says to put your entities in Spotlight so Siri can find them. It doesn't say what happens if the entity includes the answer: **Siri reads the answer from the index and skips your tool.**

| Version | What was indexed | Tool called |
|---|---|---|
| Order entity with status and arrival as properties and in the Spotlight description | Identity **and** the answer | 3 of 8 runs |
| Order entity with only `id`, `item` and `synonyms`; the tool reads status when it runs | Identity only | 4 of 4 completed runs |
| Cart; nothing indexed, the tool calls an API | Nothing | 5 of 5 runs |

In the runs that skipped the tool, Siri still gave the right facts, in its own words. If your data is cached, that looks harmless. If it has to be live, like a delivery status or an account balance, Siri gives an out-of-date answer and your code never runs.

So keep the entity to what identifies the record: its ID, its name, and the words people use for it. Fetch everything else in the tool. Also keep the Spotlight `contentDescription` and the display subtitle free of the answer.

Two more things to know:
- **Indexed names show up when your app isn't named.** "Where's my package?" called no tool, as Apple's rules require, but Siri still listed all three orders by name from the index. Don't put anything private in titles.
- **`@DeferredProperty` is untested here.** Apple's docs describe it as an async property fetched on demand, which may be the official way to keep live data out of the index.

## Calling your API from a tool

[`GetCartIntent`](app-intents/GetCartIntent.swift) fetches a cart from [DummyJSON](https://dummyjson.com) and reads it back:

> "From Siri Spike: Your cart has 4 products, $13,037.88: Blue Frock, Generic Motorcycle, iPhone 6, Baseball Ball."

- **Set a short timeout** (10 seconds here). Siri waits for `perform()`.
- **Reply on failure instead of throwing**, so the person hears what went wrong: "Couldn't reach the cart service."
- **Nothing about the cart is indexed**, so Siri called the tool in 5 of 5 runs.

## Logged-in API calls

The demo signs in when the app opens. It uses DummyJSON's public test account with a one-minute access token, so every test exercises expiry. A real Expo app usually signs in from JavaScript; reading a token saved by JavaScript is [not covered yet](#not-covered-yet).

What [`AuthService`](app-intents/AuthService.swift) does:

1. **Stores the tokens in the Keychain as readable after first unlock** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). With that setting, Siri read the cart with the phone locked. Secure-storage libraries that default to "readable only while unlocked" would probably fail there; this hasn't been tested.
2. **Calls the API with the access token.**
3. **On a 401, refreshes once, saves the new tokens and retries.** DummyJSON returns 401 for an expired token, which its docs don't say. The tool also treats 403 as expired.
4. **If the refresh fails, it replies "Open Siri Spike to sign in again."** It never loops and never fails silently.

The refresh and retry fit inside Siri's wait. The app shows what the last tool call did ("used saved token", "refreshed after 401" or "signed out"), which is how the tests tell a real refresh from a token that hadn't expired yet.

## Testing with Siri Evaluations

Apple's [Siri Evaluations](https://developer.apple.com/documentation/appintents/siri-ai-developer-preview) framework sends Siri a request and records which tools it called and what it said. It runs as a UI test on a device. **Xcode 27.3 doesn't ship it for the Simulator.**

```swift
SiriScenario {
  UserTurn("In Siri Spike, what's in my cart?") {
    Calls { getCartIntent }
    SiriResponse(.contains("motorcycle", caseSensitive: false))
  }
}
```

Run it from the command line:

```bash
xcodebuild -workspace ios/SiriSpike.xcworkspace -scheme SiriSpikeSiriEvals -configuration Release \
  -destination 'id=<device UDID>' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<team ID> IPHONEOS_DEPLOYMENT_TARGET=27.3 \
  -only-testing:'SiriSpikeSiriEvals/callsCartToolEveryTime()' test
```

What we learned:

- **Assert both the tool call and the reply.** Asserting only the reply misses Siri answering from the index; asserting only the call misses a wrong answer.
- **Run each scenario several times.** Siri varies from run to run. A single passing run proved nothing about the order tool, which Siri then didn't call in 5 of 8 runs.
- **Run a negative control once.** Expect something wrong on purpose and confirm the test fails. It did here, for the reply check and for the token refresh (with refresh turned off, every reply said to sign in again).
- **Expect some runs to be scored "ended before all of its results arrived".** This happened in up to 3 of 5 runs, even when the tool demonstrably ran and Siri gave the full reply. The evaluation counts these as failures, so a correct app can fail the suite. The cause is unknown; it happened most while Siri was also hearing a person nearby.
- **Keep the phone unlocked, on power and quiet.** Over Wi‑Fi, a locked phone ends the run with "Lost pending connection to the test runner". Set Auto-Lock to Never. Siri speaks each reply, and with "Listen for Siri" on, it may also hear you.
- **Results are attachments.** `xcrun xcresulttool export attachments --path <result bundle> --output-path <folder>` writes `.xcevalresult` JSON files, which hold each run's tool calls and Siri's reply.

## Not covered yet

- **Skills** (SKILL.md bundles that teach Siri multi-step tasks). The Xcode steps are in [SPIKE.md](SPIKE.md#build-with-siri-ai-on), but they haven't been run.
- **Entity search with the app closed** ("What coffee did I order in Siri Spike?").
- **Reading a token saved by JavaScript**, for example with `expo-secure-store`, including its Keychain accessibility setting.
- **`@DeferredProperty`** for live entity data.
- **`runBackgroundTask`**, which lets JavaScript answer Siri, once it ships in expo-app-intents.
- **Running the app below iOS 27.3** with the flag off.
- **Whether prebuild also removes a Skills Bundle** (expected, not checked).

## License

[MIT](LICENSE)
