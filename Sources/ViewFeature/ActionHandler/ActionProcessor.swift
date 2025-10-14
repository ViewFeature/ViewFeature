import Foundation

/// Action execution closure that mutates state and returns a task.
public typealias ActionExecution<Action, State> =
  @MainActor (Action, inout State) async ->
  ActionTask<Action, State>

/// Error handler closure that can mutate state in response to errors.
public typealias StateErrorHandler<State> = (Error, inout State) -> Void

/// Core action processing engine with integrated middleware pipeline.
///
/// Orchestrates action processing lifecycle: middleware execution, timing, error handling, and task transformation.
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
  public func process(action: Action, state: inout State) async -> ActionTask<Action, State> {
    let startTime = ContinuousClock.now

    do {
      let result = try await executeWithMiddleware(
        action: action, state: &state, startTime: startTime)
      return result
    } catch {
      await handleError(error: error, action: action, state: &state)
      return ActionTask.none
    }
  }

  private func executeWithMiddleware(
    action: Action,
    state: inout State,
    startTime: ContinuousClock.Instant
  ) async throws -> ActionTask<Action, State> {
    try await middlewareManager.executeBeforeAction(action: action, state: state)
    let result = await baseExecution(action, &state)
    let durationNanoseconds = startTime.duration(to: ContinuousClock.now).components.attoseconds / 1_000_000_000
    let duration = TimeInterval(durationNanoseconds) / 1_000_000_000.0  // Convert to seconds
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
  public func onError(_ handler: @escaping (Error, inout State) -> Void) -> ActionProcessor<
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
    let transformedExecution: @MainActor (Action, inout State) async -> ActionTask<Action, State> =
      { action, state in
        let result = await self.baseExecution(action, &state)
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
    state: inout State
  ) async {
    await middlewareManager.executeErrorHandling(
      error: error,
      action: action,
      state: state
    )

    errorHandler?(error, &state)
  }
}
