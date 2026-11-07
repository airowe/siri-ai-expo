import AppIntentsTesting
import Evaluations
import SiriEvaluations
import Testing
import XCTest

private let appBundleIdentifier = "com.adamrowe.sirispike"
private let definitions = IntentDefinitions(bundleIdentifier: appBundleIdentifier)
private let getOrderStatusIntent = definitions.intents["GetOrderStatusIntent"]
private let publishTimeout: TimeInterval = 90

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
}
