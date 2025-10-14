import Foundation
import Logging

/// Manages and executes middleware in an action processing pipeline.
///
/// Executes middleware at three stages: before actions, after actions (with duration), and during error handling.
/// Middleware executes in registration order. Error handling is resilient (one failure doesn't stop others).
@MainActor
public final class MiddlewareManager<Action, State> {
  private var middlewares: [any BaseActionMiddleware] = []

  private let logger: Logger

  /// Creates a new MiddlewareManager with optional initial middleware.
  public init(middlewares: [any BaseActionMiddleware] = []) {
    self.middlewares = middlewares
    let subsystem = Bundle.main.bundleIdentifier ?? "com.viewfeature.library"
    self.logger = Logger(label: "\(subsystem).MiddlewareManager")
  }

  /// Returns all currently registered middleware.
  public var allMiddlewares: [any BaseActionMiddleware] {
    middlewares
  }

  /// Adds middleware to the execution pipeline (appended to end).
  public func addMiddleware(_ middleware: some BaseActionMiddleware) {
    middlewares.append(middleware)
  }

  /// Adds multiple middleware to the execution pipeline.
  public func addMiddlewares(_ newMiddlewares: [any BaseActionMiddleware]) {
    middlewares.append(contentsOf: newMiddlewares)
  }

  /// Executes all before-action middleware. Stops if any middleware throws.
  public func executeBeforeAction(action: Action, state: State) async throws {
    let beforeMiddlewares = middlewares.compactMap { $0 as? any BeforeActionMiddleware }

    for middleware in beforeMiddlewares {
      try await middleware.beforeAction(action, state: state)
    }
  }

  /// Executes all after-action middleware with duration (in seconds).
  public func executeAfterAction(
    action: Action, state: State, result: ActionTask<Action, State>, duration: TimeInterval
  ) async throws {
    let afterMiddlewares = middlewares.compactMap { $0 as? any AfterActionMiddleware }

    for middleware in afterMiddlewares {
      try await middleware.afterAction(action, state: state, result: result, duration: duration)
    }
  }

  /// Executes all error-handling middleware. Resilient: logs but doesn't propagate middleware failures.
  public func executeErrorHandling(error: Error, action: Action, state: State) async {
    let errorMiddlewares = middlewares.compactMap { $0 as? any ErrorHandlingMiddleware }

    for middleware in errorMiddlewares {
      do {
        try await middleware.onError(error, action: action, state: state)
      } catch {
        logger.error(
          "🚨 Middleware '\(middleware.id)' failed during error handling: \(error.localizedDescription)"
        )
      }
    }
  }
}
