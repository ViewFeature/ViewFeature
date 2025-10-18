/// Internal task representation used by the store.
///
/// `StoreTask` represents the different types of tasks that can be executed
/// by the store's task management system. This is an internal type wrapped
/// by ``ActionTask`` for public API.
///
/// ## Topics
/// ### Task Cases
/// - ``none``
/// - ``run(id:operation:onError:cancelInFlight:)``
/// - ``cancel(id:)``
public enum StoreTask<Action, State> {
  /// No task to execute
  case none

  /// Execute an asynchronous operation
  ///
  /// The operation receives the current state, allowing
  /// safe state mutation within the MainActor context.
  ///
  /// - Parameters:
  ///   - id: Unique identifier for this task
  ///   - operation: The async operation to execute
  ///   - onError: Optional error handler
  ///   - cancelInFlight: If true, cancels any running task with the same id before starting this one
  case run(
    id: String,
    operation: @MainActor (State) async throws -> Void,
    onError: (@MainActor (Error, State) -> Void)?,
    cancelInFlight: Bool
  )

  /// Cancel a running task
  case cancel(id: String)
}
