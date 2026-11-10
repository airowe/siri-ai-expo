import AppIntentsTesting
import Evaluations
import SiriEvaluations
import Testing
import XCTest

private let appBundleIdentifier = "com.adamrowe.sirispike"
private let definitions = IntentDefinitions(bundleIdentifier: appBundleIdentifier)
private let getOrderStatusIntent = definitions.intents["GetOrderStatusIntent"]
private let searchOrdersIntent = definitions.intents["SearchOrdersIntent"]
private let getCartIntent = definitions.intents["GetCartIntent"]
/// A product in DummyJSON's fixed cart 1. Nothing about the cart is indexed, so naming it proves the API was called.
private let productOnlyTheAPIKnows = "motorcycle"
private let publishTimeout: TimeInterval = 90
private let reliabilityRuns = 5

/// Launches the app so it publishes its orders, then runs each scenario through Siri.
struct OrderStatusEvaluation: Evaluation {
  let name: String
  let dataset: SiriScenarioLoader

  func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject {
    try await launchAppAndWaitForPublish()
    return try await SiriService.run(scenario: sample)
  }

  var evaluators: Evaluators {
    SiriExpectationEvaluator()
  }

  func aggregateMetrics(using aggregator: inout MetricsAggregator) {
    Self.computeSiriMetrics(into: &aggregator)
  }
}

@MainActor
private func launchAppAndWaitForPublish() throws {
  let app = XCUIApplication(bundleIdentifier: appBundleIdentifier)
  app.launch()
  let status = app.staticTexts["catalog-status"]
  let finished = NSPredicate(format: "label CONTAINS 'Spotlight:'")
  let expectation = XCTNSPredicateExpectation(predicate: finished, object: status)
  let outcome = XCTWaiter().wait(for: [expectation], timeout: publishTimeout)
  print("[siri-eval] catalog status: \(status.exists ? status.label : "missing")")
  guard outcome == .completed else {
    throw PublishError.timedOut(status.exists ? status.label : "missing")
  }
}

private enum PublishError: Error {
  case timedOut(String)
}

@Test(
  .evaluates(OrderStatusEvaluation(
    name: "Trail running shoes status, app open",
    dataset: SiriScenarioLoader {
      SiriScenario {
        UserTurn("In Siri Spike, where are my trail running shoes?") {
          Calls {
            getOrderStatusIntent
          }
          SiriResponse(.contains("out for delivery", caseSensitive: false))
        }
      }
    }
  ))
)
func answersTrailRunningShoesStatus() async throws {
  let result = EvaluationContext.current.result
  #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
  #expect(result.aggregateValue(.mean(of: .siriResponseAllPass)) == 1)
}

private func trailRunningShoesScenario() -> SiriScenario {
  SiriScenario {
    UserTurn("In Siri Spike, where are my trail running shoes?") {
      Calls {
        getOrderStatusIntent
      }
      SiriResponse(.contains("out for delivery", caseSensitive: false))
    }
  }
}

@Test(
  .evaluates(OrderStatusEvaluation(
    name: "Trail running shoes status, repeated",
    dataset: SiriScenarioLoader {
      (0..<reliabilityRuns).map { _ in trailRunningShoesScenario() }
    }
  ))
)
func callsOrderStatusToolEveryTime() async throws {
  let result = EvaluationContext.current.result
  #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
  #expect(result.aggregateValue(.mean(of: .siriResponseAllPass)) == 1)
}

@Test(
  .evaluates(OrderStatusEvaluation(
    name: "Search orders for shoes, app open",
    dataset: SiriScenarioLoader {
      SiriScenario {
        UserTurn("Search my Siri Spike orders for shoes") {
          Calls {
            searchOrdersIntent
          }
          SiriResponse(.contains("trail running shoes", caseSensitive: false))
        }
      }
    }
  ))
)
func searchesOrdersByKeyword() async throws {
  let result = EvaluationContext.current.result
  #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
  #expect(result.aggregateValue(.mean(of: .siriResponseAllPass)) == 1)
}

@Test(
  .evaluates(OrderStatusEvaluation(
    name: "Package question without the app name",
    dataset: SiriScenarioLoader {
      SiriScenario {
        UserTurn("Where's my package?") {
          Calls(.disallowed) {
            getOrderStatusIntent
            searchOrdersIntent
          }
        }
      }
    }
  ))
)
func ignoresToolsWhenAppIsNotNamed() async throws {
  let result = EvaluationContext.current.result
  #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
}

private func cartScenario() -> SiriScenario {
  SiriScenario {
    UserTurn("In Siri Spike, what's in my cart?") {
      Calls {
        getCartIntent
      }
      SiriResponse(.contains(productOnlyTheAPIKnows, caseSensitive: false))
    }
  }
}

@Test(
  .evaluates(OrderStatusEvaluation(
    name: "Cart contents from the demo API, repeated",
    dataset: SiriScenarioLoader {
      (0..<reliabilityRuns).map { _ in cartScenario() }
    }
  ))
)
func callsCartToolEveryTime() async throws {
  let result = EvaluationContext.current.result
  #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
  #expect(result.aggregateValue(.mean(of: .siriResponseAllPass)) == 1)
}

/// Longer than the app's one-minute access token, so the tool must refresh it.
private let tokenExpiryWait: Duration = .seconds(70)

/// Signs in with a one-minute token, waits for it to expire, asks Siri, then prints what the tool did.
struct ExpiredTokenEvaluation: Evaluation {
  let name: String
  let dataset: SiriScenarioLoader

  func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject {
    try await launchAppAndWaitForPublish()
    try await waitForSignIn()
    try await Task.sleep(for: tokenExpiryWait)
    let subject = try await SiriService.run(scenario: sample)
    await printToolOutcome()
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
private func waitForSignIn() throws {
  let status = XCUIApplication(bundleIdentifier: appBundleIdentifier).staticTexts["auth-status"]
  let signedIn = NSPredicate(format: "label BEGINSWITH 'Signed in'")
  let expectation = XCTNSPredicateExpectation(predicate: signedIn, object: status)
  let outcome = XCTWaiter().wait(for: [expectation], timeout: publishTimeout)
  print("[siri-eval] auth status: \(status.exists ? status.label : "missing")")
  guard outcome == .completed else {
    throw PublishError.timedOut(status.exists ? status.label : "missing")
  }
}

/// Brings the app forward without relaunching it, so the outcome isn't reset by a new sign-in.
@MainActor
private func printToolOutcome() {
  let app = XCUIApplication(bundleIdentifier: appBundleIdentifier)
  app.activate()
  let outcome = app.staticTexts["tool-outcome"]
  _ = outcome.waitForExistence(timeout: 10)
  print("[siri-eval] \(outcome.exists ? outcome.label : "tool outcome missing")")
}

@Test(
  .evaluates(ExpiredTokenEvaluation(
    name: "Cart after the access token expires, repeated",
    dataset: SiriScenarioLoader {
      (0..<reliabilityRuns).map { _ in cartScenario() }
    }
  ))
)
func refreshesExpiredTokenEveryTime() async throws {
  let result = EvaluationContext.current.result
  #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
  #expect(result.aggregateValue(.mean(of: .siriResponseAllPass)) == 1)
}
