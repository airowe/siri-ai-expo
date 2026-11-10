internal import ExpoAppIntents
internal import ExpoModulesCore

/// Registered Expo inline module that wires app-target App Intents code to expo-app-intents.
/// Do not change the name of this class.
final class AppIntentsSetup: Module {
  public func definition() -> ExpoModulesCore.ModuleDefinition {
    Name("AppIntentsSetup")

    OnCreate {
      if #available(iOS 18.0, macOS 15.0, *) {
        AppEntityIdentifierRegistry.shared.registerIndexed("order", as: OrderEntity.self)
      }
    }

    AsyncFunction("signInAsync") { () async throws in
      try await AuthService.signIn()
    }

    Function("signOut") {
      AuthService.signOut()
    }

    Function("lastToolOutcome") { () -> String in
      ToolOutcome.last
    }
  }
}
