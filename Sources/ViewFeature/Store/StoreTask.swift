/// Internal task representation used by the store.
///
/// `StoreTask` represents the different types of tasks that can be executed
/// by the store's task management system. This is an internal type wrapped
/// by ``ActionTask`` for public API.
///
/// ## Topics
/// ### Task Cases
/// - ``none``
/// - ``run(id:operation:onError:)``
/// - ``cancel(id:)``
public enum StoreTask<Action, State> {
  /// No task to execute
  case none

  /// Execute an asynchronous operation
  case run(
    id: String,
    operation: () async throws -> Void,
    onError: ((Error, inout State) -> Void)? = nil
  )

  /// Cancel a running task
  case cancel(id: String)
}

