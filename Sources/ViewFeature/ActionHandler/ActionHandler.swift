import Foundation

/// A facade for action processing with fluent method chaining capabilities.
///
/// `ActionHandler` provides a clean, composable API for defining how your feature
/// processes actions and updates state. It supports:
/// - Direct state mutation through `inout` parameters
/// - Asynchronous task execution
/// - Error handling
/// - Debug logging
/// - Task transformation
///
/// ## Basic Usage
/// ```swift
/// struct MyFeature: StoreFeature {
///   @MainActor
///   @Observable
///   final class State {
///     var count = 0
///     var isLoading = false
///     var data: [Item] = []
///   }
///
///   enum Action: Sendable {
///     case increment
///     case loadData
///     case dataLoaded([Item])
///   }
///
///   func handle() -> ActionHandler<Action, State> {
///     ActionHandler { action, state in
///       switch action {
///       case .increment:
///         state.count += 1
///         return .none
///       case .loadData:
///         state.isLoading = true
///         return .run(id: "load-data") {
///           // Perform async operation
///           try await Task.sleep(for: .seconds(1))
///           // Note: After task completes, dispatch .dataLoaded
///           // from the View layer: store.send(.dataLoaded(data))
///         }
///       case .dataLoaded(let items):
///         state.data = items
///         state.isLoading = false
///         return .none
///       }
///     }
///   }
/// }
/// ```
///
/// ## Method Chaining
/// Enhance your handler with additional functionality:
/// ```swift
/// struct MyFeature: StoreFeature {
///   @MainActor
///   @Observable
///   final class State {
///     var errorMessage: String?
///   }
///
///   enum Action: Sendable {
///     case doSomething
///   }
///
///   func handle() -> ActionHandler<Action, State> {
///     ActionHandler { action, state in
///       // action processing
///       return .none
///     }
///     .onError { error, state in
///       state.errorMessage = error.localizedDescription
///     }
///     .withDebug(category: "MyFeature")
///   }
/// }
/// ```
///
/// ## Topics
/// ### Creating Handlers
/// - ``init(_:)``
///
/// ### Processing Actions
/// - ``handle(action:state:)``
///
/// ### Method Chaining
/// - ``onError(_:)``
/// - ``withDebug(category:)``
/// - ``transform(_:)``
public final class ActionHandler<Action, State> {
  private let processor: ActionProcessor<Action, State>

  /// Creates an ActionHandler with the given action processing logic.
  ///
  /// - Parameter actionLogic: A closure that processes actions and mutates state.
  ///   The closure receives an action and an `inout` state parameter, and returns
  ///   an ``ActionTask`` for any asynchronous side effects.
  ///
  /// ## Example
  /// ```swift
  /// struct CounterFeature: StoreFeature {
  ///   @MainActor
  ///   @Observable
  ///   final class State {
  ///     var count = 0
  ///   }
  ///
  ///   enum Action: Sendable {
  ///     case increment
  ///   }
  ///
  ///   func handle() -> ActionHandler<Action, State> {
  ///     ActionHandler { action, state in
  ///       switch action {
  ///       case .increment:
  ///         state.count += 1
  ///         return .none
  ///       }
  ///     }
  ///   }
  /// }
  /// ```
  public init(_ actionLogic: @escaping ActionExecution<Action, State>) {
    self.processor = ActionProcessor(actionLogic)
  }

  private init(processor: ActionProcessor<Action, State>) {
    self.processor = processor
  }

  /// Processes an action and updates the state.
  ///
  /// - Parameters:
  ///   - action: The action to process
  ///   - state: The current state (will be mutated)
  /// - Returns: An ``ActionTask`` containing any asynchronous side effects
  public func handle(action: Action, state: inout State) async -> ActionTask<Action, State> {
    await processor.process(action: action, state: &state)
  }
}

// MARK: - Method Chaining Extensions

extension ActionHandler {
  /// Adds error handling to the action processing pipeline.
  ///
  /// The error handler is called when any error occurs during action processing
  /// or task execution. It receives the error and an `inout` state parameter,
  /// allowing you to update the state based on the error.
  ///
  /// - Parameter errorHandler: A closure that handles errors
  /// - Returns: A new ActionHandler with error handling
  ///
  /// ## Example
  /// ```swift
  /// handler.onError { error, state in
  ///   state.errorMessage = error.localizedDescription
  ///   state.isLoading = false
  /// }
  /// ```
  public func onError(_ errorHandler: @escaping (Error, inout State) -> Void) -> ActionHandler<Action, State> {
    ActionHandler(processor: processor.onError(errorHandler))
  }

  /// Adds debug logging to the action processing pipeline.
  ///
  /// Logs action start, completion (with duration), and any errors that occur.
  /// This is useful during development to track action flow.
  ///
  /// - Parameter category: The logging category (default: "ViewFeature.ActionHandler")
  /// - Returns: A new ActionHandler with debug logging
  ///
  /// ## Example
  /// ```swift
  /// handler.withDebug(category: "UserFeature")
  /// ```
  ///
  /// - Note: Consider removing debug logging in production builds for performance
  public func withDebug(
    category: String = "ViewFeature.ActionHandler"
  ) -> ActionHandler<Action, State> {
    return use(LoggingMiddleware(category: category))
  }

  /// Transforms the task returned by action processing.
  ///
  /// Allows you to modify or wrap the ``ActionTask`` returned by your action handler.
  /// Useful for adding cross-cutting concerns or decorating tasks.
  ///
  /// - Parameter taskTransform: A closure that transforms the task
  /// - Returns: A new ActionHandler with task transformation
  ///
  /// ## Example
  /// ```swift
  /// handler.transform { task in
  ///   // Add automatic error handling to all tasks
  ///   switch task.storeTask {
  ///   case .run(let id, let operation, _):
  ///     return .run(id: id) {
  ///       do {
  ///         try await operation()
  ///       } catch {
  ///         print("Task failed: \(error)")
  ///         throw error
  ///       }
  ///     }
  ///   default:
  ///     return task
  ///   }
  /// }
  /// ```
  public func transform(_ taskTransform: @escaping (ActionTask<Action, State>) -> ActionTask<Action, State>) -> ActionHandler<Action, State> {
    ActionHandler(processor: processor.transform(taskTransform))
  }

  private func use(_ middleware: some BaseActionMiddleware) -> ActionHandler<Action, State> {
    ActionHandler(processor: processor.use(middleware))
  }
}
