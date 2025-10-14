import Foundation
import Logging

/// Manages and executes middleware in an action processing pipeline.
///
/// Executes middleware at three stages: before actions, after actions (with duration), and during error handling.
/// Middleware executes in registration order.
///
/// ## Error Propagation Semantics
///
/// ### Before-Action and After-Action Middleware (Fail-Fast)
/// - Errors thrown by `beforeAction` or `afterAction` **propagate immediately**
/// - Action processing **stops** if any middleware throws
/// - Subsequent middleware in the pipeline **will not execute**
/// - Use case: Critical validation that must succeed (auth checks, rate limiting)
///
/// ### Error-Handling Middleware (Resilient)
/// - Errors thrown by `onError` are **caught and logged only**
/// - Error handling **continues** even if one middleware fails
/// - All error handlers get a chance to execute
/// - Use case: Best-effort logging/telemetry that shouldn't block recovery
///
/// ## Example
/// ```swift
/// // Before-action middleware that validates auth (fail-fast)
/// struct AuthMiddleware: BeforeActionMiddleware {
///   func beforeAction(_ action: Action, state: State) async throws {
///     guard state.isAuthenticated else {
///       throw AuthError.notAuthenticated  // Stops action processing
///     }
///   }
/// }
///
/// // Error-handling middleware for logging (resilient)
/// struct ErrorLoggingMiddleware: ErrorHandlingMiddleware {
///   func onError(_ error: Error, action: Action, state: State) async throws {
///     // Even if this throws, other error handlers still run
///     try await sendToAnalytics(error)
///   }
/// }
/// ```
@MainActor
public final class MiddlewareManager<Action, State> {
  private var middlewares: [any BaseActionMiddleware] = []

  // Cached middleware lists for performance (computed once at initialization)
  private var beforeMiddlewares: [any BeforeActionMiddleware] = []
  private var afterMiddlewares: [any AfterActionMiddleware] = []
  private var errorMiddlewares: [any ErrorHandlingMiddleware] = []

  private let logger: Logger

  /// Creates a new MiddlewareManager with optional initial middleware.
  public init(middlewares: [any BaseActionMiddleware] = []) {
    self.middlewares = middlewares
    let subsystem = Bundle.main.bundleIdentifier ?? "com.viewfeature.library"
    self.logger = Logger(label: "\(subsystem).MiddlewareManager")

    // Cache filtered middleware lists for performance
    self.beforeMiddlewares = middlewares.compactMap { $0 as? any BeforeActionMiddleware }
    self.afterMiddlewares = middlewares.compactMap { $0 as? any AfterActionMiddleware }
    self.errorMiddlewares = middlewares.compactMap { $0 as? any ErrorHandlingMiddleware }
  }

  /// Returns all currently registered middleware.
  public var allMiddlewares: [any BaseActionMiddleware] {
    middlewares
  }

  /// Adds middleware to the execution pipeline (appended to end).
  public func addMiddleware(_ middleware: some BaseActionMiddleware) {
    middlewares.append(middleware)

    // Update cached middleware lists
    if let before = middleware as? any BeforeActionMiddleware {
      beforeMiddlewares.append(before)
    }
    if let after = middleware as? any AfterActionMiddleware {
      afterMiddlewares.append(after)
    }
    if let error = middleware as? any ErrorHandlingMiddleware {
      errorMiddlewares.append(error)
    }
  }

  /// Adds multiple middleware to the execution pipeline.
  public func addMiddlewares(_ newMiddlewares: [any BaseActionMiddleware]) {
    middlewares.append(contentsOf: newMiddlewares)

    // Update cached middleware lists
    beforeMiddlewares.append(contentsOf: newMiddlewares.compactMap { $0 as? any BeforeActionMiddleware })
    afterMiddlewares.append(contentsOf: newMiddlewares.compactMap { $0 as? any AfterActionMiddleware })
    errorMiddlewares.append(contentsOf: newMiddlewares.compactMap { $0 as? any ErrorHandlingMiddleware })
  }

  /// Executes all before-action middleware in registration order.
  ///
  /// **Fail-Fast Semantics**: If any middleware throws, execution stops immediately and the error propagates.
  /// Use for critical pre-conditions (authentication, rate limiting, feature flags).
  ///
  /// - Throws: The first error thrown by any middleware
  public func executeBeforeAction(action: Action, state: State) async throws {
    for middleware in beforeMiddlewares {
      try await middleware.beforeAction(action, state: state)
    }
  }

  /// Executes all after-action middleware with timing information.
  ///
  /// **Fail-Fast Semantics**: If any middleware throws, execution stops immediately and the error propagates.
  /// Use for critical post-processing (transaction commits, cache invalidation).
  ///
  /// - Parameter duration: Execution duration in seconds (from start of action processing)
  /// - Throws: The first error thrown by any middleware
  public func executeAfterAction(
    action: Action, state: State, result: ActionTask<Action, State>, duration: TimeInterval
  ) async throws {
    for middleware in afterMiddlewares {
      try await middleware.afterAction(action, state: state, result: result, duration: duration)
    }
  }

  /// Executes all error-handling middleware in registration order.
  ///
  /// **Resilient Semantics**: If a middleware throws, the error is logged and execution continues.
  /// All error handlers are guaranteed to run. Use for best-effort telemetry/logging.
  ///
  /// - Note: Never throws - middleware failures are logged but not propagated
  public func executeErrorHandling(error: Error, action: Action, state: State) async {
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
