# SiriAIKit JavaScript bridge: design

**Date:** Nov 11, 2026
**Status:** Design. Nothing is built. Blocked on Expo releasing `runBackgroundTask`, and on the cold-start measurement on the iPhone below. JavaScript does start on a cold launch ([checked on the Simulator](#will-javascript-start-at-all)).
**Inputs:** [the Expo layer spike](https://github.com/airowe/siri-ai-expo/blob/spike/expo-layer/docs/spikes/expo-layer.md) (`spike/expo-layer`: `patches/`, `app-intents/GetPackingTipIntent.swift`, `siriTasks.ts`), SiriAIKit 0.2.0's `SiriTool.swift`, `ToolFailure.swift` and `ToolOutcomeLog.swift`.

## Goal

Let an Expo app answer a Siri AI tool from JavaScript, and keep what `SiriTool` gives a Swift tool:

- Siri's time budget (`timeout`, 10 s by default);
- failures turned into sentences Siri can say (`ToolFailure` → `ToolReplies`);
- an outcome with notes that an evaluation can read (`ToolOutcomeLog`).

The tool's declaration stays in Swift. Siri needs a Swift `AppIntent` with `@AppIntent(.tool)`, and Apple's metadata extraction reads it at build time. Only the answer comes from JavaScript. The Swift can be hand-written, or generated at prebuild by the `tools` option that the codegen spike adds ([airowe/siri-ai-kit#8](https://github.com/airowe/siri-ai-kit/pull/8)); see [Generated tools](#generated-tools).

## Summary

| Question | Answer |
|---|---|
| Can it work? | Yes. The spike's `GetPackingTipIntent` passed 3 of 3 Siri evaluations on a device, with Expo's `runBackgroundTask` backported. |
| Is it usable? | Unknown. Those runs were all **warm**: the evaluation launches the app before each run. Nobody has measured a cold start inside Siri's wait. |
| Will JavaScript even start on a cold launch? | **Yes** (Simulator, `AppIntentsTesting`, 3 of 3). iOS connects a background scene, so React Native starts. Cold: ~1.7 s before `perform()`, then 0.2–0.3 s to the JS reply. Warm: 1–10 ms. Device timing is still unmeasured. |
| Has Expo shipped it? | No. It's on Expo's `main` (since Oct 27), but not on `sdk-58` and not in any npm release (checked below). |
| What would we ship? | A Swift method on `SiriTool` and a JavaScript `defineSiriTool` in `expo-siri-ai-kit`. No new plugin option: JS-answered tools become one more kind of declaration in #8's `tools` option. No native module. |
| What ships now? | Nothing. Measure cold start first. |

## Where Expo is (checked Nov 11, 2026)

`runBackgroundTask` is four stacked PRs:

- [expo/expo#51592](https://github.com/expo/expo/pull/51592): task-manager reports JS errors to native callers
- [#51593](https://github.com/expo/expo/pull/51593): event responses and atomic registration
- [#51594](https://github.com/expo/expo/pull/51594): the on-demand task runner (`EXTaskRunner`)
- [#51595](https://github.com/expo/expo/pull/51595): `AppIntentDispatcher.runBackgroundTask(name:params:timeout:)`

| Check | Result |
|---|---|
| Merged into `main`? | **Yes.** All four merge commits are ancestors of `main`. `packages/expo-app-intents/ios/AppIntentBackgroundTask.swift` exists there, added by `45d1f6f4e9` (#51595) on Oct 27. |
| On the `sdk-58` release branch? | **No.** That file returns 404 on `sdk-58`. |
| `expo-app-intents@0.5.17` (latest, published Nov 11) | No `runBackgroundTask`, no `AppIntentBackgroundTask.swift`. |
| `expo-task-manager@58.0.14` (latest, Nov 11) | No `TaskRunner`/`OnDemandTask`, no `ERR_TASK_EXECUTION_FAILED` in `build/TaskManager.js`. |
| `expo-modules-core@58.1.0` (latest, Nov 11) | No `EXTaskRunnerInterface`. |

Each tarball was also searched for a string it must contain (`AppIntentDispatcher`, `EXTaskServiceInterface`, `defineTask`), and each search found it, so the empty results above are real.

This corrects the spike write-up, which says the stack was merged into a feature branch rather than `main`. (The stack was merged bottom-up into each other's branches, and then reached `main`.)

**Inference, not confirmed:** Expo publishes SDK 58 patches from `sdk-58`, so this most likely ships with SDK 59, unless Expo cherry-picks it. Re-check with the commands in [Re-checking Expo](#re-checking-expo).

## What an app author writes

### Swift: the tool

```swift
import AppIntents
internal import ExpoAppIntents
import SiriAIKit

private let tool = SiriTool(appName: "Trips")

#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct GetPackingTipIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Packing Tip"
  static let description = IntentDescription("Gives the person one tip for packing for a trip.")

  @Parameter(title: "Destination") var destination: String

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let answer = await tool.answer(javaScript: { timeout in
      try await AppIntentDispatcher.shared.runBackgroundTask(
        name: "packing-tip",
        params: ["destination": .string(destination)],
        timeout: timeout
      )
    })
    return .result(value: answer, dialog: "\(answer)")
  }
}
```

New in SiriAIKit:

```swift
extension SiriTool {
  /// How much longer than `timeout` the JavaScript run may take, so `SiriTool`'s deadline always fires first.
  public static let javaScriptGrace: Duration = .seconds(2)

  /// Runs a JavaScript task through `run`, passing it `timeout + javaScriptGrace`, and answers with its reply,
  /// or with the sentence Siri should say instead.
  public func answer<Reply: Encodable & Sendable>(
    javaScript run: @escaping @Sendable (_ timeout: Duration) async throws -> Reply
  ) async -> String

  /// The JavaScript task's answer, or a `ToolFailure`.
  public func run<Reply: Encodable & Sendable>(
    javaScript run: @escaping @Sendable (_ timeout: Duration) async throws -> Reply
  ) async throws(ToolFailure) -> String
}
```

**Why a closure instead of calling Expo from SiriAIKit:** SiriAIKit is a Swift package; `ExpoAppIntents` is a CocoaPod compiled into the app. SiriAIKit can't import it. The closure keeps SiriAIKit free of Expo, so the reply handling is unit-testable on macOS like the rest of the library. The app's line of glue is the `runBackgroundTask` call it would write anyway.

**Why `Encodable`:** the closure returns Expo's `AppIntentValue`, which encodes as plain JSON (a single-value container per case, checked in `AppIntentValue.swift` in 0.5.17). SiriAIKit encodes it with `JSONEncoder` and decodes the reply described below. It never names Expo's type.

### JavaScript: the answer

```ts
// siriTools.ts, imported from the app's entry file (index.ts)
import { defineSiriTool, ToolFailure } from 'expo-siri-ai-kit';

defineSiriTool('packing-tip', async ({ params, note }) => {
  const token = await loadToken();
  if (!token) throw new ToolFailure('signedOut');

  const response = await fetch(`https://api.example.com/tips?to=${encodeURIComponent(String(params.destination))}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (response.status === 401) {
    note('token rejected');
    throw new ToolFailure('signedOut');
  }
  const { tip } = await response.json();
  return `Here's a tip for ${params.destination}: ${tip}`;
});
```

```ts
type ToolFailureKind = 'signedOut' | 'timedOut' | 'unreachable' | 'failed';

export class ToolFailure extends Error {
  constructor(readonly kind: ToolFailureKind, message?: string);
}

export type SiriToolContext = {
  /** The tool's parameters, as Swift passed them to runBackgroundTask. */
  params: Record<string, unknown>;
  /** Adds a detail to this run's outcome, as ToolOutcomeLog.note does in Swift. */
  note(detail: string): void;
};

export function defineSiriTool(
  name: string,
  answer: (context: SiriToolContext) => Promise<string>,
  options?: { classify?: (error: unknown) => ToolFailureKind | undefined },
): void;
```

`defineSiriTool` calls `TaskManager.defineTask<AppIntentInvocation>(name, …)`. The same rule applies as for `defineTask`: **call it at the top level of a module the entry file imports.** A tool defined in a component or a lazily loaded screen doesn't exist when Siri launches the app in the background, and the run fails as "not defined".

## The reply contract

`defineSiriTool` never lets the executor throw. It always resolves with a reply:

```json
{ "siriAIKit": 1, "answer": "Here's a tip for Lisbon: …", "notes": ["cache hit"] }
{ "siriAIKit": 1, "failure": "signedOut", "notes": ["token rejected"] }
```

- `siriAIKit` is the contract version. Swift rejects other versions as `.failed` with the note `unsupported reply version N`.
- Exactly one of `answer` (a string) or `failure` (one of the four kinds) is present.
- `notes` are in the order `note` was called.

Why an envelope instead of letting JavaScript throw: a thrown JS error reaches Swift only as an `NSError` whose message is `The task 'x' threw an error in JavaScript: <message>` (`OnDemandTaskException.failed`). There's no code, so Swift would have to parse English to tell "signed out" from "unreachable". It also can't carry notes. The envelope carries both.

A task that returns a bare string (as `siriTasks.ts` does in the spike) is accepted as an answer with no notes, so a plain `defineTask` still works.

## How SiriTool's behaviour maps across the bridge

`answer(javaScript:)` is `answer { … }` with the JavaScript call as the operation. All of `SiriTool.run`'s rules still hold: one deadline, `classify` first, the outcome recorded once, late notes dropped.

### Timeout

- `SiriTool.timeout` is the only budget the author sets.
- SiriAIKit passes `timeout + javaScriptGrace` to the closure, which hands it to `runBackgroundTask`. **The runner's own timeout must never fire first.** If it did, Swift would get an `NSError` ("did not finish within …") and record `failed` instead of `timed out`, and Siri would say "something went wrong" instead of "took too long".
- At `SiriTool`'s deadline the wait ends, as for any operation. The JavaScript task keeps running. When it finishes, Expo drops the reply (the continuation was already taken) and its notes are dropped (the run's notes are closed).
- A JavaScript task that times out in Swift can still finish its work. As Expo's docs say, pass an idempotency key in `params` when a retried tool must not apply something twice.

### Failures

| What happens | What Swift sees | `ToolFailure` | Outcome |
|---|---|---|---|
| JS returns a string | `{answer}` | — | `succeeded (notes…)` |
| JS throws `new ToolFailure('signedOut')` | `{failure: "signedOut"}` | `.signedOut` | `signed out (notes…)` |
| JS `fetch` fails with no network (`TypeError: Network request failed`) | `{failure: "unreachable"}` (default `classify`) | `.unreachable` | `unreachable (…)` |
| JS throws anything else | `{failure: "failed"}` plus the note `JS threw TypeError` (the error's `name`, not its message) | `.failed` | `failed (JS threw TypeError; …)` |
| JS is slower than `timeout` | `SiriTool`'s deadline | `.timedOut` | `timed out (Swift notes only)` |
| Siri cancels `perform()` | cancellation | `.timedOut` | `timed out` |
| Task not defined, unregistered mid-run, or name taken | `NSError` from the runner | `.failed` | `failed (JS task error: <first 100 characters of the message>)` |
| `expo-task-manager` not installed | `BackgroundTaskUnavailableException` | `.failed` | `failed (JS task error: …)` |
| Reply is neither an envelope nor a string | decoding fails | `.failed` | `failed (unexpected reply from JS)` |
| Envelope names an unknown failure | — | `.failed` | `failed (unknown failure 'x')` |

- The app's Swift `classify` still runs first, on errors thrown by the closure. It never sees envelope failures: those are already `ToolFailure`s.
- Error *messages* stay out of notes on the JS side, because the outcome is shown on screen and can end up in evaluation logs. Runner messages are Expo's own text, so they're safe to include.
- The default JS `classify` only knows the React Native network error. An app passes `options.classify` for its own errors, mirroring Swift.

### Notes

`ToolOutcomeLog.note` uses a task-local (`RunNotes.current`), so it only works inside the run's operation. JS notes ride in the reply, and SiriAIKit adds them with `note` when the reply arrives, before the outcome is recorded. They appear after any notes Swift made before the call, in the same outcome:

```
succeeded (cache hit) at 14:02:11
signed out (token rejected) at 14:03:40
```

## Cold vs warm

| App state when Siri calls | What happens before JS can answer | Spike evidence |
|---|---|---|
| **Foreground**, JS running | The runner emits an event; the executor runs on the JS thread. Milliseconds. | 3 of 3 passed on the iPhone; 1–10 ms on the Simulator |
| **Suspended**, process alive | iOS resumes the process for the intent; the JS thread resumes, then runs the task (after any timers or work queued while suspended). | None |
| **Cold**, no process | iOS launches the app in the background. Native start, Expo modules, the React Native host, Hermes loads the bundle and evaluates the entry file (its whole import graph, including `App` and the code that runs on launch), `defineSiriTool` registers, then the task runs. All of it counts against `SiriTool.timeout`, because the runner's clock starts when Swift calls it. | Simulator, without Siri: 3 of 3 answered ([below](#will-javascript-start-at-all)) |

### Will JavaScript start at all?

**Yes. Checked on the Simulator on Nov 11, 2026.** A cold launch for an intent starts React Native, and the JavaScript task answers.

Why this needed checking: in SDK 58 (and on Expo's `main`), React Native starts only in `ExpoAppSceneDelegate.scene(_:willConnectTo:options:)`, and expo-task-manager's fallback for starting JavaScript asks for a `"react-native-experience"` app loader that nothing registers in a standalone app. If a background launch connected no scene, the task would wait in `EXTaskService`'s queue until the runner timed out. It does connect one.

**How it was run:** a copy of the spike app (`spike/expo-layer` with the backport patches), with the [instrumentation](#instrumentation) below plus two more notes: `scenes` (`UIApplication.shared.connectedScenes.count` in `perform()`) and `appState` (`applicationState`, 0 active, 2 background). `GetPackingTipIntent` returned the outcome with its answer. A UI test target ran it through `AppIntentsTesting` (`IntentDefinitions(...).intents["GetPackingTipIntent"].makeIntent().run()`), on a new iPhone 18 Pro Simulator, iOS 27.3 (24C5037i), Xcode 27.3 beta, Release build. Cold runs called `launch()`, `terminate()`, waited 3 s, then ran the intent (XCUIApplication state before: 1, not running). Warm runs launched the app once and ran the intent three times.

| Run | `scenes` | `appState` | `proc` | `boot` | `task` | `reply` | Test's wall time |
|---|---|---|---|---|---|---|---|
| cold 1 | 1 | 2 (background) | 1783 ms | +11 ms | 157 ms | 170 ms | 2878 ms |
| cold 2 | 1 | 2 (background) | 1587 ms | +197 ms | 320 ms | 327 ms | 2044 ms |
| cold 3 | 1 | 2 (background) | 1644 ms | +103 ms | 229 ms | 236 ms | 2005 ms |
| warm 1 | 1 | 0 (active) | 7739 ms | −5253 ms | 2 ms | 10 ms | 162 ms |
| warm 2 | 1 | 0 (active) | 7790 ms | −5304 ms | 0 ms | 1 ms | 13 ms |
| warm 3 | 1 | 0 (active) | 7803 ms | −5317 ms | 0 ms | 1 ms | 13 ms |

What it shows:

- **A background scene connects on a cold intent launch.** `scenes=1` with the app in the background (and in the background afterwards, XCUIApplication state 3). So `ExpoAppSceneDelegate` starts React Native, and no extra native start-up code is needed.
- **Every cold run was really cold.** `boot` is positive: JavaScript evaluated the entry file after `perform()` was called. Warm runs have JS running 5 s before.
- **Most of the cold cost comes before `perform()`.** About 1.6–1.8 s passes between the process starting and `perform()` (`proc`), then 0.2–0.3 s to the JavaScript reply. The test's wall time, 2–2.9 s, covers both. Whatever Siri sees includes the whole thing.
- **Warm is free:** 1–10 ms.

What it doesn't show:

- **Device timing.** A Mac's Simulator is faster than a phone. The [measurement on the iPhone](#cold-start-measurement) is still needed for the decision.
- **That Siri launches the app the same way.** `AppIntentsTesting` runs the intent without Siri. Siri on the Simulator doesn't work ([airowe/siri-ai-kit#7](https://github.com/airowe/siri-ai-kit/pull/7)). The device measurement's `scenes` and `boot` notes will show whether Siri's launch matches.

Earlier drafts of this spec predicted, from reading the code, that no scene would connect and JavaScript would never start. That was wrong, which is why it was checked before reporting anything to Expo.

Things that follow:

- **Only Release builds are meaningful.** A development build loads JS from Metro, so a cold start depends on the Mac and the network, and may fail outright (Expo's own timeout message says to open the project in the app once first).
- **The app's launch work competes with the task.** In the spike app, `App.tsx` publishes Spotlight items and signs in when it mounts. In a cold background launch that work runs on the same JS thread as the tool.
- **Cold is the common case for Siri.** People ask Siri when they're not in the app. If a tool only works warm, it doesn't work.
- If cold start is too slow, the options are, in order: keep that tool in Swift (SiriAIKit 0.2.0 today); trim what the entry file does at launch; raise `SiriTool.timeout`, but only if the measurement shows Siri waits that long.

## What we'd ship

Phased, so nothing ships that only works with patched Expo.

### Now: nothing new

- No JavaScript API. It needs `patch-package` over three Expo packages and `EXPO_USE_PRECOMPILED_MODULES=0`, which most apps won't accept.
- Run the cold-start measurement below on the spike branch.
- Leave the spike's `GetPackingTipIntent` and `siriTasks.ts` as the reference.

### When Expo releases `runBackgroundTask` and cold start passes

**SiriAIKit 0.3.0**

- `SiriTool.answer(javaScript:)`, `SiriTool.run(javaScript:)` and `javaScriptGrace`.
- Reply decoding as an internal type, unit-tested on macOS.
- No dependency on Expo.

**`expo-siri-ai-kit` 0.3.0**

- A JavaScript entry: `defineSiriTool`, `ToolFailure`, and the types above. `app.plugin.js` stays the config plugin; Expo resolves the plugin from `app.plugin.js` before `main`, so `main` can point at the runtime build.
- `expo-task-manager` and `expo-app-intents` (from the first SDK that has `runBackgroundTask`) as peer dependencies.
- The plugin default moves to SiriAIKit 0.3.0.
- README: a "Tools answered by JavaScript" section with the two snippets above, the top-level-definition rule, the measured cold-start numbers, and when to keep a tool in Swift.

**Not shipped, and why:**

- **A native module.** The bridge already exists (`runBackgroundTask`). The Swift side has to live in the app target anyway, because that's where the tool's `AppIntent` is. A cold launch connects a background scene, so Expo's own start-up runs React Native and no start-up code of ours is needed ([checked](#will-javascript-start-at-all)).
- **A separate plugin option** (for example `javascriptTools: true`). There's nothing extra to configure natively, and Expo's own error already says to install `expo-task-manager`. Generated JS-answered tools go through the existing `tools` option instead (next section).

### Generated tools

The codegen spike ([airowe/siri-ai-kit#8](https://github.com/airowe/siri-ai-kit/pull/8), not merged, not run on a device) adds a `tools` option that generates one `@AppIntent(.tool)` Swift file per tool from a JSON declaration at prebuild. Its tools answer from an HTTP request and a reply template.

A JavaScript-answered tool fits as another answer kind in that declaration, so the app author writes no Swift at all:

```json
{
  "name": "GetPackingTip",
  "title": "Get Packing Tip",
  "description": "Gives the person one tip for packing for a trip.",
  "parameters": [{ "name": "destination", "type": "string", "title": "Destination" }],
  "javascript": "packing-tip"
}
```

- The generator writes the `perform()` shown in [Swift: the tool](#swift-the-tool): every parameter goes into `params` under its own name (the same `name` the declaration uses, which is what JavaScript reads), and the answer comes from `tool.answer(javaScript:)`.
- `javascript` replaces both `request` and `reply`: JavaScript writes the whole answer. Validation rejects a tool that has `javascript` together with either, and a project without `expo-task-manager`.
- Parameters map to `AppIntentValue` by type: `string`, `int`, `double`, `bool` directly; `enum` as its case name; `date` as an ISO 8601 string, because `AppIntentValue` has no date.
- The generated file needs `internal import ExpoAppIntents`, which #8's request-based tools don't. #8's typecheck script would need Expo's sources to check these files, so they're checked by building the Expo app instead.
- This is the same `tools` option, so it waits for #8 to merge and for the bridge itself. Without #8, apps write the Swift by hand.

### If cold start fails

Document why in the `expo-siri-ai-kit` README ("Tools answered by JavaScript: not supported, because …" with the numbers) and keep tools in Swift.

## Testing the bridge (when it's built)

TDD, as for the rest of SiriAIKit.

- **SiriAIKit unit tests** (`swift test`, macOS), with stub closures instead of Expo:
  - one parameterized test over every row of the failure table, asserting the `ToolFailure`, the outcome and the notes;
  - the closure receives `timeout + javaScriptGrace`;
  - a closure slower than `timeout` gives `.timedOut`, and notes it returns afterwards are dropped;
  - a bare string reply is an answer;
  - Swift notes made before the call come before JS notes.
- **Jest tests** for `defineSiriTool`, with `expo-task-manager` mocked: the envelope for an answer, for each `ToolFailure` kind, for a network `TypeError`, for any other throw (name only, no message), and with a custom `classify`.
- **On a device**: the spike's packing-tip evaluation rewritten with `answer(javaScript:)`, cold and warm, plus a negative control (a JS `ToolFailure('signedOut')` must make Siri say the sign-in sentence, and the reply check for the tip must fail).

## Cold-start measurement

**Run this before building anything above.** The [Simulator check](#will-javascript-start-at-all) showed JavaScript starts on a cold launch and how the time splits; this measures it on the phone, through Siri. Add the Simulator check's `scenes` and `appState` notes to the instrumentation, to confirm Siri's launch looks the same. It answers:

1. How long from `perform()` to the JavaScript reply, warm and cold?
2. Do cold runs pass the Siri evaluation inside a 10-second `SiriTool`?
3. If a cold start takes longer than 10 seconds, does Siri wait for it?

### Design

- **Tool:** the spike's `GetPackingTipIntent`, still on the patched `runBackgroundTask`. Its task does no network or storage work, so it measures the bridge and JS start-up only. A real tool adds its own API time on top.
- **Timeout:** raised to 30 seconds for the measurement (runner: 32 seconds, per the grace rule), so slow cold starts are measured rather than cut off at 9 seconds. Whether the run would have passed at 10 seconds is computed from the numbers afterwards.
- **States:** warm (app in the foreground, JS running) and cold (process terminated), 5 runs each. Suspended is optional, 5 runs, if there's time.
- **Classifying each run:** by the data, not by what the test intended. A run is cold when JS started *after* `perform()` was called (`boot` is positive). This also guards against iOS prewarming, which can start a process before it's needed; a prewarmed process shows a large `proc` age but still a positive `boot`.
- **Clock:** Swift `Date.now` and JavaScript `Date.now()` in the same process, both epoch milliseconds.

### Instrumentation

All of it goes on a measurement branch of the spike app (`spike/cold-start` off `spike/expo-layer`), never into SiriAIKit.

**JavaScript, `bootClock.ts`**, imported first in `index.ts`, so its timestamp is taken before the rest of the bundle evaluates:

```ts
/** When this JS runtime evaluated the entry file. */
export const BOOT_AT = Date.now();
```

```ts
// index.ts: the first import
import './bootClock';
import { registerRootComponent } from 'expo';
// …unchanged
```

**JavaScript, `siriTasks.ts`**: return timestamps with the tip.

```ts
import { BOOT_AT } from './bootClock';

TaskManager.defineTask<AppIntentInvocation>(PACKING_TIP_TASK, async () => {
  const taskAt = Date.now();
  const tip = TIPS[new Date().getSeconds() % TIPS.length];
  return { tip: `Here's a tip from JavaScript: ${tip}`, bootAt: BOOT_AT, taskAt };
});
```

**Swift, `GetPackingTipIntent.swift`**: notes through `ToolOutcomeLog.standard.note`, as `key=value` so they're easy to pull out of logs.

```swift
import Darwin

private let packingTipTool = SiriTool(appName: "Siri Spike", timeout: .seconds(30))

private enum PackingTipError: Error {
  case unexpectedReply
}

private func epochMilliseconds(_ date: Date) -> Int {
  Int((date.timeIntervalSince1970 * 1000).rounded())
}

/// When this process started, from the kernel. Earlier than launch if iOS prewarmed the app.
private func processStart() -> Date? {
  var info = kinfo_proc()
  var size = MemoryLayout<kinfo_proc>.stride
  var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
  guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
  let start = info.kp_proc.p_un.__p_starttime
  return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
}

struct GetPackingTipIntent: AppIntent {
  // title and description unchanged

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let performAt = epochMilliseconds(.now)
    let answer = await packingTipTool.answer {
      let log = ToolOutcomeLog.standard
      log.note("t0=\(performAt)")
      if let start = processStart() {
        log.note("proc=\(performAt - epochMilliseconds(start))ms")
      }
      let value = try await AppIntentDispatcher.shared.runBackgroundTask(
        name: "packing-tip", timeout: .seconds(32)
      )
      let replyAt = epochMilliseconds(.now)
      guard case .object(let reply) = value,
            case .string(let tip)? = reply["tip"],
            case .int(let bootAt)? = reply["bootAt"],
            case .int(let taskAt)? = reply["taskAt"]
      else { throw PackingTipError.unexpectedReply }
      log.note("boot=\(bootAt - performAt)ms")
      log.note("task=\(taskAt - performAt)ms")
      log.note("reply=\(replyAt - performAt)ms")
      return tip
    }
    return .result(value: answer, dialog: "\(answer)")
  }
}
```

What each note means, all relative to `perform()`:

| Note | Meaning |
|---|---|
| `t0` | When `perform()` ran (epoch ms), to line runs up with the outcome's `at` time. |
| `proc` | How old the process was. Small: launched for this call. Large: already running, or prewarmed. |
| `boot` | When JS evaluated the entry file. **Positive: cold.** Negative: JS was already running (warm or suspended). |
| `task` | When the executor started. `task − boot` is the time from evaluating the bundle to running the task. |
| `reply` | When Swift had the answer. **This is the number that matters.** |

If Siri gives up first, the outcome is `timed out (t0=…; proc=…)` with no `reply`, and its `at` time shows roughly when.

`kp_proc.p_un.__p_starttime` is how Swift imports `p_starttime`. If it doesn't compile, drop `proc`; the other notes still classify the run.

**Evaluations, `siri-evals/OrderStatusEvaluationTests.swift`**: an evaluation that sets the app's state before each run and prints the outcome afterwards.

```swift
private let coldStartRuns = 5

enum StartState {
  case warm, suspended, cold
}

struct ColdStartEvaluation: Evaluation {
  let name: String
  let start: StartState
  let dataset: SiriScenarioLoader

  func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject {
    try await prepare(start)
    let subject = try await SiriService.run(scenario: sample)
    await printPackingTipOutcome()
    return subject
  }

  var evaluators: Evaluators {
    SiriExpectationEvaluator()
  }

  func aggregateMetrics(using aggregator: inout MetricsAggregator) {
    Self.computeSiriMetrics(into: &aggregator)
  }
}

@MainActor
private func prepare(_ start: StartState) async throws {
  let app = XCUIApplication(bundleIdentifier: appBundleIdentifier)
  switch start {
  case .warm:
    try launchAppAndWaitForPublish()
  case .suspended:
    try launchAppAndWaitForPublish()
    XCUIDevice.shared.press(.home)
    try await Task.sleep(for: .seconds(10))
  case .cold:
    app.launch() // so the test runner owns the process it terminates
    app.terminate()
    try await Task.sleep(for: .seconds(5))
  }
}

/// Brings the app forward without relaunching it and prints the last outcome, notes included.
@MainActor
private func printPackingTipOutcome() async {
  let app = XCUIApplication(bundleIdentifier: appBundleIdentifier)
  app.activate()
  let outcome = app.staticTexts["siri-ai-tool-outcome"]
  _ = outcome.waitForExistence(timeout: 30)
  try? await Task.sleep(for: .seconds(3)) // App.tsx polls the outcome; let it pick up this run's
  print("[cold-start] \(outcome.exists ? outcome.label : "tool outcome missing")")
}

private func packingTipScenarios() -> [SiriScenario] {
  (0..<coldStartRuns).map { _ in
    SiriScenario {
      UserTurn("In Siri Spike, give me a packing tip.") {
        Calls { getPackingTipIntent }
        SiriResponse(.contains("from JavaScript", caseSensitive: false))
      }
    }
  }
}

@Test(.evaluates(ColdStartEvaluation(
  name: "Packing tip, warm", start: .warm, dataset: SiriScenarioLoader { packingTipScenarios() }
)))
func packingTipWhenWarm() async throws {}

@Test(.evaluates(ColdStartEvaluation(
  name: "Packing tip, cold", start: .cold, dataset: SiriScenarioLoader { packingTipScenarios() }
)))
func packingTipWhenCold() async throws {}

@Test(.evaluates(ColdStartEvaluation(
  name: "Packing tip, suspended", start: .suspended, dataset: SiriScenarioLoader { packingTipScenarios() }
)))
func packingTipWhenSuspended() async throws {}
```

- The test bodies assert nothing on purpose: a failed Siri check must not stop the timings from being collected. `siri-ai-eval summarize` reports the pass rates.
- **Forcing a cold start:** `launch()` then `terminate()` kills the process, then 5 seconds pass before Siri is asked. Siri then has to launch the app. This is a cold process with a warm OS file cache, which is the realistic case for an app used recently. A reboot would also clear the file cache, but it breaks the test runner's connection, so it's out of scope.
- **A stale read** shows up as two runs with the same `t0`. Discard the later one.
- `printPackingTipOutcome` reads `siri-ai-tool-outcome`, which `App.tsx` already renders from `ToolOutcomeLog.standard.last`. Its label says "Last quote tool call:"; that's cosmetic.

### Procedure

1. Device as in the spike README: unlocked, on power, Auto-Lock set to Never, a quiet room, "Listen for Siri" off.
2. Build Release only (no Metro).
3. Run warm, then cold, then (optionally) suspended. Re-run any run that `siri-ai-eval` scores as incomplete ("ended before all of its results arrived") until there are 5 complete runs of each.
4. Put each run's notes and its Siri result in one table:

| State | Run | `proc` | `boot` | `task` | `reply` | Outcome | Siri call | Siri reply |
|---|---|---|---|---|---|---|---|---|

5. Report median and maximum `reply` per state, and how many cold runs had `reply` under 10 000 ms.
6. Write the results up as `docs/spikes/cold-start.md` on the spike branch.

### Decision

| Cold `reply`, worst of 5, and every cold run's Siri reply passed | Decision |
|---|---|
| ≤ 5 s | Viable. Build the bridge as specified, with the 10-second default. |
| 5–8 s | Viable with care. Build it; the README states the cost and recommends trimming launch work. |
| > 8 s, or any cold run timed out or failed Siri's checks | Not viable as the default path. Don't ship a JS API; document why. |

5 seconds leaves half of the default budget for the tool's own network call, which this probe doesn't make. If any cold run passes 10 seconds, its Siri result answers question 3.

### Commands

Run on the Mac with the iPhone attached, in `~/Projects/siri-ai-expo`, once the spike's uncommitted work on `spike/expo-layer` is committed. Replace `<UDID>` and `<TEAM_ID>`.

```bash
cd ~/Projects/siri-ai-expo
```

```bash
git switch -c spike/cold-start spike/expo-layer
```

Apply the instrumentation above (`bootClock.ts`, `index.ts`, `siriTasks.ts`, `app-intents/GetPackingTipIntent.swift`, `siri-evals/OrderStatusEvaluationTests.swift`), then:

```bash
npm install
```

```bash
SIRI_AI_PREVIEW=1 CI=1 npx expo prebuild --clean --no-install -p ios
```

```bash
ruby scripts/add-siri-eval-target.rb
```

```bash
cd ios && EXPO_USE_PRECOMPILED_MODULES=0 CP_CACHE_DIR="$PWD/../.cp-cache" LANG=en_US.UTF-8 pod install && cd ..
```

```bash
xcrun devicectl list devices
```

```bash
mkdir -p results/cold-start
```

```bash
xcodebuild -workspace ios/SiriSpike.xcworkspace -scheme SiriSpikeSiriEvals -configuration Release \
  -destination 'id=<UDID>' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<TEAM_ID> IPHONEOS_DEPLOYMENT_TARGET=27.3 \
  -resultBundlePath results/cold-start/warm.xcresult \
  -only-testing:'SiriSpikeSiriEvals/packingTipWhenWarm()' test 2>&1 | tee results/cold-start/warm.log
```

```bash
xcodebuild -workspace ios/SiriSpike.xcworkspace -scheme SiriSpikeSiriEvals -configuration Release \
  -destination 'id=<UDID>' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<TEAM_ID> IPHONEOS_DEPLOYMENT_TARGET=27.3 \
  -resultBundlePath results/cold-start/cold.xcresult \
  -only-testing:'SiriSpikeSiriEvals/packingTipWhenCold()' test 2>&1 | tee results/cold-start/cold.log
```

Optional:

```bash
xcodebuild -workspace ios/SiriSpike.xcworkspace -scheme SiriSpikeSiriEvals -configuration Release \
  -destination 'id=<UDID>' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<TEAM_ID> IPHONEOS_DEPLOYMENT_TARGET=27.3 \
  -resultBundlePath results/cold-start/suspended.xcresult \
  -only-testing:'SiriSpikeSiriEvals/packingTipWhenSuspended()' test 2>&1 | tee results/cold-start/suspended.log
```

Timings per run:

```bash
grep -h '\[cold-start\]' results/cold-start/warm.log results/cold-start/cold.log
```

Siri pass rates, with incomplete runs reported separately:

```bash
swift run --package-path ~/Projects/siri-ai-kit siri-ai-eval summarize results/cold-start/warm.xcresult
```

```bash
swift run --package-path ~/Projects/siri-ai-kit siri-ai-eval summarize results/cold-start/cold.xcresult
```

`results/` holds result bundles; don't commit it.

## Re-checking Expo

`runBackgroundTask` has shipped when this prints a path:

```bash
mkdir -p "$SCRATCH/eai" && npm pack expo-app-intents@latest --pack-destination "$SCRATCH/eai" && tar -xzf "$SCRATCH"/eai/*.tgz -C "$SCRATCH/eai" && grep -rl 'func runBackgroundTask' "$SCRATCH/eai/package/ios"
```

(`$SCRATCH` is any scratch folder.) And on the release branch:

```bash
gh api 'repos/expo/expo/contents/packages/expo-app-intents/ios/AppIntentBackgroundTask.swift?ref=sdk-59' --jq .name
```

## Open questions

- **How long Siri waits for a tool.** `SiriTool`'s 10 seconds is our choice, not Apple's limit. The measurement only answers this if a cold run passes 10 seconds.
- **How much the app's own launch work costs a cold run.** A background scene connects, so React Native mounts `App`, and its launch work (Spotlight publishing and sign-in in the spike) shares the JS thread with the tool. On the Simulator `task − boot` was 120–150 ms. The device numbers will show whether apps need a "launched for Siri" check.
- **The first SDK with `runBackgroundTask`**, and whether its API matches the backport. The bridge's Swift side depends only on the closure shape, so a renamed method changes the app's glue line, not SiriAIKit.
