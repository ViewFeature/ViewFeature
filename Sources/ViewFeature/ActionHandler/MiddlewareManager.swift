import Foundation
import Logging

/// Manages and executes middleware in an action processing pipeline.
///
/// `MiddlewareManager` orchestrates the execution of middleware at different stages
/// of action processing: before actions, after actions, and during error handling.
/// It maintains a collection of middleware and executes them based on their protocol
/// conformance using the Interface Segregation Principle (ISP).
///
/// ## Architecture Role
/// MiddlewareManager is used by ``ActionProcessor`` to execute the middleware pipeline:
/// - **Before Action**: Validates, logs, or prepares for action execution
/// - **After Action**: Records metrics, triggers analytics, or performs cleanup
/// - **Error Handling**: Logs errors, reports to services, or performs recovery
///
/// ## Key Features
/// - Protocol-based middleware execution (ISP compliance)
/// - Order-preserving execution
/// - Error resilience (one middleware failure doesn't stop others)
/// - Dynamic middleware registration
/// - Type-safe middleware management
///
/// ## Usage
/// MiddlewareManager is typically used internally by ``ActionProcessor``:
/// ```swift
/// let manager = MiddlewareManager<MyAction, MyState>()
/// manager.addMiddleware(LoggingMiddleware())
/// manager.addMiddleware(AnalyticsMiddleware())
///
/// // Execute before action
/// try await manager.executeBeforeAction(action: .login, state: currentState)
///
/// // Execute after action with duration
/// try await manager.executeAfterAction(
///   action: .login,
///   state: newState,
///   result: task,
///   duration: 0.123
/// )
///
/// // Execute error handling
/// await manager.executeErrorHandling(
///   error: someError,
///   action: .login,
///   state: currentState
/// )
/// ```
///
/// ## Middleware Execution Order
/// Middleware executes in the order it's added:
/// ```swift
/// manager.addMiddleware(middleware1)  // Executes first
/// manager.addMiddleware(middleware2)  // Executes second
/// manager.addMiddleware(middleware3)  // Executes third
/// ```
///
/// ## Protocol-Based Execution
/// Only middleware conforming to the appropriate protocol executes at each stage:
/// - ``BeforeActionMiddleware``: Only runs during `executeBeforeAction`
/// - ``AfterActionMiddleware``: Only runs during `executeAfterAction`
/// - ``ErrorHandlingMiddleware``: Only runs during `executeErrorHandling`
/// - ``ActionMiddleware``: Runs during all three stages (composite protocol)
///
/// ## Error Resilience
/// If a middleware throws an error during error handling:
/// - The error is logged but not propagated
/// - Remaining error middleware still executes
/// - This prevents error handling from failing catastrophically
///
/// ## Topics
/// ### Creating a Manager
/// - ``init(middlewares:)``
///
/// ### Managing Middleware
/// - ``addMiddleware(_:)``
/// - ``addMiddlewares(_:)``
/// - ``allMiddlewares``
///
/// ### Executing Middleware
/// - ``executeBeforeAction(action:state:)``
/// - ``executeAfterAction(action:state:result:duration:)``
/// - ``executeErrorHandling(error:action:state:)``
public final class MiddlewareManager<Action, State> {
  private var middlewares: [any BaseActionMiddleware] = []

  private let logger: Logger

  /// Creates a new MiddlewareManager with optional initial middleware.
  ///
  /// - Parameter middlewares: Array of middleware to initialize with (default: empty)
  ///
  /// ## Example
  /// ```swift
  /// // Empty manager
  /// let manager = MiddlewareManager<MyAction, MyState>()
  ///
  /// // Pre-populated manager
  /// let manager = MiddlewareManager(middlewares: [
  ///   LoggingMiddleware(),
  ///   AnalyticsMiddleware()
  /// ])
  /// ```
  public init(middlewares: [any BaseActionMiddleware] = []) {
    self.middlewares = middlewares
    let subsystem = Bundle.main.bundleIdentifier ?? "com.viewfeature.library"
    self.logger = Logger(label: "\(subsystem).MiddlewareManager")
  }

  /// Returns all currently registered middleware.
  ///
  /// Use this property to inspect the middleware stack or create copies of the manager.
  ///
  /// ## Example
  /// ```swift
  /// print("Registered middleware:")
  /// for middleware in manager.allMiddlewares {
  ///   print("  - \(middleware.id)")
  /// }
  /// ```
  public var allMiddlewares: [any BaseActionMiddleware] {
    middlewares
  }

  /// Adds a single middleware to the execution pipeline.
  ///
  /// The middleware is appended to the end of the execution order.
  ///
  /// - Parameter middleware: The middleware to add
  ///
  /// ## Example
  /// ```swift
  /// let manager = MiddlewareManager<MyAction, MyState>()
  /// manager.addMiddleware(LoggingMiddleware())
  /// manager.addMiddleware(AnalyticsMiddleware())
  /// ```
  public func addMiddleware(_ middleware: some BaseActionMiddleware) {
    middlewares.append(middleware)
  }

  /// Adds multiple middleware to the execution pipeline.
  ///
  /// All middleware are appended in the order provided.
  ///
  /// - Parameter newMiddlewares: Array of middleware to add
  ///
  /// ## Example
  /// ```swift
  /// manager.addMiddlewares([
  ///   LoggingMiddleware(),
  ///   AnalyticsMiddleware(),
  ///   ValidationMiddleware()
  /// ])
  /// ```
  public func addMiddlewares(_ newMiddlewares: [any BaseActionMiddleware]) {
    middlewares.append(contentsOf: newMiddlewares)
  }

  /// Executes all before-action middleware for the given action.
  ///
  /// Only middleware conforming to ``BeforeActionMiddleware`` will execute.
  /// Execution stops if any middleware throws an error.
  ///
  /// - Parameters:
  ///   - action: The action about to be processed
  ///   - state: The current state (read-only)
  /// - Throws: Any error thrown by middleware (stops execution)
  ///
  /// ## Example
  /// ```swift
  /// do {
  ///   try await manager.executeBeforeAction(
  ///     action: .login(credentials),
  ///     state: currentState
  ///   )
  ///   // All before-action middleware passed
  /// } catch {
  ///   // A middleware rejected the action
  ///   print("Action rejected: \(error)")
  /// }
  /// ```
  ///
  /// ## Use Cases
  /// - Validate action preconditions
  /// - Log action start events
  /// - Check permissions or authorization
  /// - Verify state invariants
  public func executeBeforeAction(action: Action, state: State) async throws {
    let beforeMiddlewares = middlewares.compactMap { $0 as? any BeforeActionMiddleware }

    for middleware in beforeMiddlewares {
      try await middleware.beforeAction(action, state: state)
    }
  }

  /// Executes all after-action middleware for the completed action.
  ///
  /// Only middleware conforming to ``AfterActionMiddleware`` will execute.
  /// All middleware execute even if some throw errors (errors are propagated after all execute).
  ///
  /// - Parameters:
  ///   - action: The action that was processed
  ///   - state: The updated state (read-only)
  ///   - result: The task returned by the action handler
  ///   - duration: Time taken to process the action (in seconds)
  /// - Throws: Any error thrown by middleware
  ///
  /// ## Example
  /// ```swift
  /// try await manager.executeAfterAction(
  ///   action: .login(credentials),
  ///   state: newState,
  ///   result: loginTask,
  ///   duration: 0.234
  /// )
  /// ```
  ///
  /// ## Use Cases
  /// - Log action completion with duration
  /// - Send analytics events
  /// - Update performance metrics
  /// - Trigger dependent actions
  /// - Verify state postconditions
  ///
  /// ## Duration Format
  /// Duration is provided in seconds as `TimeInterval`. Middleware typically
  /// converts to milliseconds for display: `duration * 1000`
  public func executeAfterAction(
    action: Action, state: State, result: ActionTask<Action, State>, duration: TimeInterval
  ) async throws {
    let afterMiddlewares = middlewares.compactMap { $0 as? any AfterActionMiddleware }

    for middleware in afterMiddlewares {
      try await middleware.afterAction(action, state: state, result: result, duration: duration)
    }
  }

  /// Executes all error-handling middleware for the given error.
  ///
  /// Only middleware conforming to ``ErrorHandlingMiddleware`` will execute.
  /// This method is resilient to middleware failures: if a middleware throws an error
  /// during error handling, the error is logged but doesn't stop execution of remaining middleware.
  ///
  /// - Parameters:
  ///   - error: The error that occurred
  ///   - action: The action that caused the error
  ///   - state: The current state (read-only)
  ///
  /// ## Example
  /// ```swift
  /// await manager.executeErrorHandling(
  ///   error: networkError,
  ///   action: .fetchData,
  ///   state: currentState
  /// )
  /// ```
  ///
  /// ## Use Cases
  /// - Log errors with context
  /// - Report to error tracking services (Sentry, Bugsnag)
  /// - Send error analytics
  /// - Trigger error recovery actions
  /// - Display error notifications
  ///
  /// ## Error Resilience
  /// This method never throws. If a middleware's error handler fails:
  /// ```
  /// 🚨 Middleware 'MyMiddleware' failed during error handling: <error description>
  /// ```
  /// The error is logged and execution continues with the next middleware.
  /// This prevents cascading failures in error handling.
  ///
  /// - Note: This method does not throw to ensure error handling always completes
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
