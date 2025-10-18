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
///   func onError(_ error: Error, action: Action, state: State) async {
///     // Handle errors explicitly when calling throwing functions
///     do {
///       try await sendToAnalytics(error)
///     } catch {
///       logger.warning("Analytics failed: \(error)")
///     }
///   }
/// }
/// ```
@MainActor
public final class MiddlewareManager<Action, State> {
    private var middlewares: [any BaseActionMiddleware] = []

    // Cached middleware lists for performance (computed at initialization and when middleware is added)
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
    ///
    /// Equivalent to calling ``addMiddleware(_:)`` for each middleware in the array.
    /// Order is preserved.
    ///
    /// - Parameter newMiddlewares: Array of middleware to add
    public func addMiddlewares(_ newMiddlewares: [any BaseActionMiddleware]) {
        for middleware in newMiddlewares {
            addMiddleware(middleware)
        }
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
    /// **Resilient Semantics**: All error handlers are guaranteed to execute.
    /// Error handlers cannot throw and must handle errors internally using `do-catch` or `try?`.
    ///
    /// - Note: This method never throws. All error handlers will execute to completion.
    public func executeErrorHandling(error: Error, action: Action, state: State) async {
        for middleware in errorMiddlewares {
            await middleware.onError(error, action: action, state: state)
        }
    }
}
