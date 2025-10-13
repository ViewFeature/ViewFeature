import Foundation

/// Type alias for action execution closure.
///
/// Defines the signature for action processing logic that mutates state and returns a task.
///
/// - Parameters:
///   - action: The action to process
///   - state: The mutable state reference
/// - Returns: An ``ActionTask`` for any asynchronous side effects
public typealias ActionExecution<Action, State> = @MainActor (Action, inout State) async -> ActionTask<Action, State>

/// Type alias for error handling closure.
///
/// Defines the signature for error handlers that can mutate state in response to errors.
///
/// - Parameters:
///   - error: The error that occurred
///   - state: The mutable state reference
public typealias StateErrorHandler<State> = (Error, inout State) -> Void

/// Core action processing engine with integrated middleware pipeline.
///
/// `ActionProcessor` is the internal workhorse that powers ``ActionHandler``'s fluent API.
/// It orchestrates the complete action processing lifecycle including middleware execution,
/// timing, error handling, and task transformation.
///
/// ## Architecture Role
/// ActionProcessor sits between ``ActionHandler`` (public facade) and ``MiddlewareManager``:
/// - **Input**: Receives actions and state from ActionHandler
/// - **Processing**: Executes middleware pipeline and action logic
/// - **Output**: Returns tasks and handles errors
///
/// ## Processing Pipeline
/// Each action flows through this pipeline:
/// 1. **Timing Start**: Record start time for duration measurement
/// 2. **Before Middleware**: Execute all ``BeforeActionMiddleware``
/// 3. **Action Logic**: Run the core action execution
/// 4. **After Middleware**: Execute all ``AfterActionMiddleware`` with duration
/// 5. **Error Handling**: If any step throws, execute error middleware
///
/// ## Method Chaining
/// ActionProcessor supports immutable method chaining for configuration:
/// ```swift
/// processor
///   .use(LoggingMiddleware())
///   .onError { error, state in
///     state.errorMessage = error.localizedDescription
///   }
///   .transform { task in
///     // Modify task
///   }
/// ```
///
/// Each method returns a new ActionProcessor instance, preserving immutability.
///
/// ## Usage
/// ActionProcessor is typically created internally by ``ActionHandler``:
/// ```swift
/// let handler = ActionHandler { action, state in
///   // This closure becomes the ActionProcessor's base execution
///   switch action {
///   case .increment:
///     state.count += 1
///     return .none
///   }
/// }
/// ```
///
/// ## Advanced Usage
/// For direct usage (advanced scenarios):
/// ```swift
/// let processor = ActionProcessor<MyAction, MyState> { action, state in
///   // Action logic
///   return .none
/// }
/// .use(LoggingMiddleware())
/// .onError { error, state in
///   state.errorMessage = "\(error)"
/// }
///
/// var state = MyState()
/// let task = await processor.process(action: .someAction, state: &state)
/// ```
///
/// ## Topics
/// ### Creating Processors
/// - ``init(_:)``
///
/// ### Processing Actions
/// - ``process(action:state:)``
///
/// ### Configuration Methods
/// - ``use(_:)``
/// - ``onError(_:)``
/// - ``transform(_:)``
///
/// ### Type Aliases
/// - ``ActionExecution``
/// - ``StateErrorHandler``
public final class ActionProcessor<Action, State> {
  private let baseExecution: ActionExecution<Action, State>
  private let errorHandler: StateErrorHandler<State>?
  private let middlewareManager: MiddlewareManager<Action, State>

  /// Creates an ActionProcessor with the given action execution logic.
  ///
  /// This is the primary initializer used by ``ActionHandler`` to create a processor
  /// with default configuration (no middleware, no error handler).
  ///
  /// - Parameter execution: A closure that processes actions and mutates state
  ///
  /// ## Example
  /// ```swift
  /// let processor = ActionProcessor<CounterAction, CounterState> { action, state in
  ///   switch action {
  ///   case .increment:
  ///     state.count += 1
  ///     return .none
  ///   case .decrement:
  ///     state.count -= 1
  ///     return .none
  ///   }
  /// }
  /// ```
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

  /// Processes an action through the complete middleware pipeline.
  ///
  /// This is the main entry point for action processing. It orchestrates:
  /// - Timing measurement for performance tracking
  /// - Before-action middleware execution
  /// - Core action logic execution
  /// - After-action middleware execution with duration
  /// - Error handling if any step fails
  ///
  /// - Parameters:
  ///   - action: The action to process
  ///   - state: The current state (will be mutated)
  /// - Returns: An ``ActionTask`` containing any asynchronous side effects
  ///
  /// ## Example
  /// ```swift
  /// var state = CounterState(count: 0)
  /// let task = await processor.process(action: .increment, state: &state)
  /// // state.count is now 1
  /// ```
  ///
  /// ## Error Handling
  /// If any middleware or the action logic throws an error:
  /// 1. Error middleware is executed
  /// 2. The configured error handler (if any) is called
  /// 3. Returns ``ActionTask/none``
  ///
  /// - Note: This method is called by ``ActionHandler/handle(action:state:)``
  public func process(action: Action, state: inout State) async -> ActionTask<Action, State> {
    let startTime = CFAbsoluteTimeGetCurrent()

    do {
      let result = try await executeWithMiddleware(action: action, state: &state, startTime: startTime)
      return result
    } catch {
      await handleError(error: error, action: action, state: &state)
      return ActionTask.none
    }
  }

  private func executeWithMiddleware(
    action: Action,
    state: inout State,
    startTime: CFAbsoluteTime
  ) async throws -> ActionTask<Action, State> {
    try await middlewareManager.executeBeforeAction(action: action, state: state)
    let result = await baseExecution(action, &state)
    let duration = CFAbsoluteTimeGetCurrent() - startTime
    try await middlewareManager.executeAfterAction(action: action, state: state, result: result, duration: duration)
    return result
  }

  /// Adds middleware to the processing pipeline.
  ///
  /// Creates a new ActionProcessor with the added middleware. This method supports
  /// method chaining for fluent API design. Middleware is executed in the order it's added.
  ///
  /// - Parameter middleware: The middleware to add
  /// - Returns: A new ActionProcessor with the middleware added
  ///
  /// ## Example
  /// ```swift
  /// let processor = ActionProcessor { action, state in
  ///   // Action logic
  /// }
  /// .use(LoggingMiddleware(category: "MyFeature"))
  /// .use(AnalyticsMiddleware())
  /// .use(ValidationMiddleware())
  /// ```
  ///
  /// ## Middleware Execution Order
  /// - **Before-action**: Executes in the order added (first added runs first)
  /// - **After-action**: Executes in the order added
  /// - **Error handling**: All error middleware execute regardless of order
  ///
  /// ## Multiple Middleware Types
  /// You can mix different middleware protocol conformances:
  /// ```swift
  /// processor
  ///   .use(loggingMiddleware)        // ActionMiddleware (all 3 protocols)
  ///   .use(validationMiddleware)     // BeforeActionMiddleware only
  ///   .use(analyticsMiddleware)      // AfterActionMiddleware only
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

  /// Adds error handling to the processing pipeline.
  ///
  /// Creates a new ActionProcessor with the specified error handler. The handler is called
  /// after all error middleware has executed, allowing you to update state based on errors.
  ///
  /// - Parameter handler: A closure that handles errors and can mutate state
  /// - Returns: A new ActionProcessor with error handling configured
  ///
  /// ## Example
  /// ```swift
  /// let processor = ActionProcessor { action, state in
  ///   // Action logic
  /// }
  /// .onError { error, state in
  ///   state.errorMessage = error.localizedDescription
  ///   state.isLoading = false
  ///   state.hasError = true
  /// }
  /// ```
  ///
  /// ## Error Handling Order
  /// When an error occurs:
  /// 1. All error-handling middleware execute first
  /// 2. Then this error handler executes
  /// 3. State mutations from both are preserved
  ///
  /// ## Common Patterns
  /// ```swift
  /// // Reset loading state on error
  /// .onError { error, state in
  ///   state.isLoading = false
  /// }
  ///
  /// // Store error for UI display
  /// .onError { error, state in
  ///   state.lastError = error
  /// }
  ///
  /// // Differentiate error types
  /// .onError { error, state in
  ///   switch error {
  ///   case let networkError as NetworkError:
  ///     state.networkErrorMessage = networkError.localizedDescription
  ///   case let validationError as ValidationError:
  ///     state.validationErrors = validationError.errors
  ///   default:
  ///     state.genericError = error.localizedDescription
  ///   }
  /// }
  /// ```
  public func onError(_ handler: @escaping (Error, inout State) -> Void) -> ActionProcessor<Action, State> {
    ActionProcessor(
      execution: baseExecution,
      errorHandler: handler,
      middlewareManager: middlewareManager
    )
  }

  /// Transforms the task returned by action processing.
  ///
  /// Creates a new ActionProcessor that applies a transformation to every task returned
  /// by the action logic. This allows you to add cross-cutting concerns or modify task
  /// behavior globally.
  ///
  /// - Parameter transform: A closure that transforms action tasks
  /// - Returns: A new ActionProcessor with task transformation applied
  ///
  /// ## Example: Add Logging to All Tasks
  /// ```swift
  /// processor.transform { task in
  ///   switch task.storeTask {
  ///   case .run(let id, let operation, _):
  ///     return .run(id: id) {
  ///       print("Task \(id ?? "unknown") starting...")
  ///       try await operation()
  ///       print("Task \(id ?? "unknown") completed")
  ///     }
  ///   default:
  ///     return task
  ///   }
  /// }
  /// ```
  ///
  /// ## Example: Add Timeout to All Tasks
  /// ```swift
  /// processor.transform { task in
  ///   switch task.storeTask {
  ///   case .run(let id, let operation, _):
  ///     return ActionTask.run(id: id) {
  ///       try await withTimeout(seconds: 30) {
  ///         try await operation()
  ///       }
  ///     }
  ///   default:
  ///     return task
  ///   }
  /// }
  /// ```
  ///
  /// ## Example: Automatic Error Handling
  /// ```swift
  /// processor.transform { task in
  ///   switch task.storeTask {
  ///   case .run(let id, let operation, _):
  ///     return ActionTask.run(id: id) {
  ///       do {
  ///         try await operation()
  ///       } catch {
  ///         // Automatically send error action
  ///         await store.send(.errorOccurred(error))
  ///         throw error
  ///       }
  ///     }
  ///   default:
  ///     return task
  ///   }
  /// }
  /// ```
  ///
  /// - Note: The transformation is applied after action logic but before task execution
  public func transform(_ transform: @escaping (ActionTask<Action, State>) -> ActionTask<Action, State>) -> ActionProcessor<Action, State> {
    let transformedExecution: @MainActor (Action, inout State) async -> ActionTask<Action, State> = { action, state in
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
