import Foundation

/// Action execution closure that mutates state and returns a task.
public typealias ActionExecution<Action, State> =
    @MainActor (Action, State) async ->
    ActionTask<Action, State>

/// Error handler closure that can mutate state in response to errors.
public typealias StateErrorHandler<State> = (Error, State) -> Void

/// Core action processing engine with integrated middleware pipeline.
///
/// `ActionProcessor` orchestrates the complete action processing lifecycle on the **MainActor**:
/// middleware execution, timing, error handling, and task transformation. All action processing
/// occurs on MainActor, ensuring thread-safe state mutations and seamless SwiftUI integration.
///
/// Supports immutable method chaining via `use()`, `onError()`, and `transform()`.
///
/// ```swift
/// let processor = ActionProcessor { action, state in
///   switch action {
///   case .increment: state.count += 1; return .none
///   }
/// }
/// .use(LoggingMiddleware())
/// .onError { error, state in state.errorMessage = "\(error)" }
/// ```
public final class ActionProcessor<Action, State> {
    private let baseExecution: ActionExecution<Action, State>
    private let errorHandler: StateErrorHandler<State>?
    private let middlewareManager: MiddlewareManager<Action, State>

    /// Creates an ActionProcessor with the given action execution logic.
    public init(_ execution: @escaping ActionExecution<Action, State>) {
        self.baseExecution = execution
        self.errorHandler = nil
        self.middlewareManager = MiddlewareManager()
    }

    internal init(
        execution: @escaping ActionExecution<Action, State>,
        errorHandler: StateErrorHandler<State>?,
        middlewareManager: MiddlewareManager<Action, State>
    ) {
        self.baseExecution = execution
        self.errorHandler = errorHandler
        self.middlewareManager = middlewareManager
    }

    /// Processes an action through the middleware pipeline.
    ///
    /// Executes before-action middleware, action logic, after-action middleware, and error handling if needed.
    public func process(action: Action, state: State) async -> ActionTask<Action, State> {
        let startTime = ContinuousClock.now

        // ========================================
        // Middleware Execution Flow
        // ========================================
        // Order of execution:
        // 1. Before-action middleware (line 68)
        // 2. Action logic (baseExecution, line 69)
        // 3. After-action middleware (line 73-74)
        // 4. Error middleware + error handler (line 58-60, if error thrown)
        //
        // Why this order?
        // - Before: Setup (logging, validation, state preparation)
        // - Action: Core business logic
        // - After: Cleanup (analytics, side effects tracking)
        // - Error: Recovery (error logging, state rollback)
        //
        // This order ensures middleware can observe and react to the complete action lifecycle.
        do {
            let result = try await executeWithMiddleware(
                action: action, state: state, startTime: startTime)
            return result
        } catch {
            await handleError(error: error, action: action, state: state)
            return ActionTask.none
        }
    }

    private func executeWithMiddleware(
        action: Action,
        state: State,
        startTime: ContinuousClock.Instant
    ) async throws -> ActionTask<Action, State> {
        try await middlewareManager.executeBeforeAction(action: action, state: state)
        let result = await baseExecution(action, state)
        let elapsed = startTime.duration(to: ContinuousClock.now)
        let duration = TimeInterval(elapsed.components.seconds) +
            TimeInterval(elapsed.components.attoseconds) / 1e18
        try await middlewareManager.executeAfterAction(
            action: action, state: state, result: result, duration: duration)
        return result
    }

    /// Adds middleware to the processing pipeline. Middleware is executed in the order added.
    ///
    /// ```swift
    /// processor
    ///   .use(LoggingMiddleware())
    ///   .use(AnalyticsMiddleware())
    /// ```
    public func use(_ middleware: some BaseActionMiddleware) -> ActionProcessor<Action, State> {
        let newMiddlewareManager = MiddlewareManager<Action, State>(
            middlewares: middlewareManager.allMiddlewares + [middleware]
        )

        return ActionProcessor(
            execution: baseExecution,
            errorHandler: errorHandler,
            middlewareManager: newMiddlewareManager
        )
    }

    /// Adds error handling to the processing pipeline. Called after error middleware executes.
    ///
    /// ```swift
    /// processor.onError { error, state in
    ///   state.errorMessage = error.localizedDescription
    ///   state.isLoading = false
    /// }
    /// ```
    public func onError(_ handler: @escaping (Error, State) -> Void) -> ActionProcessor<
        Action, State
    > {
        ActionProcessor(
            execution: baseExecution,
            errorHandler: handler,
            middlewareManager: middlewareManager
        )
    }

    /// Transforms the task returned by action processing.
    ///
    /// Useful for adding cross-cutting concerns like logging, timeouts, or error handling to all tasks.
    ///
    /// ```swift
    /// processor.transform { task in
    ///   switch task.storeTask {
    ///   case .run(let id, let operation, _):
    ///     return .run(id: id) { state in
    ///       print("Task \(id ?? "unknown") starting")
    ///       try await operation(state)
    ///     }
    ///   default: return task
    ///   }
    /// }
    /// ```
    public func transform(
        _ transform: @escaping (ActionTask<Action, State>) -> ActionTask<Action, State>
    ) -> ActionProcessor<Action, State> {
        let transformedExecution: @MainActor (Action, State) async -> ActionTask<Action, State> =
            { action, state in
                let result = await self.baseExecution(action, state)
                return transform(result)
            }

        return ActionProcessor(
            execution: transformedExecution,
            errorHandler: errorHandler,
            middlewareManager: middlewareManager
        )
    }

    // MARK: - Private Helpers

    private func handleError(
        error: Error,
        action: Action,
        state: State
    ) async {
        await middlewareManager.executeErrorHandling(
            error: error,
            action: action,
            state: state
        )

        errorHandler?(error, state)
    }
}
