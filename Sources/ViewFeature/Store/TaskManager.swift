import Foundation

/// Manages asynchronous task execution and lifecycle within the Store.
///
/// `TaskManager` provides robust task management with automatic cleanup and cancellation support.
/// It tracks running tasks by unique identifiers and ensures proper resource management through
/// automatic deallocation when tasks complete.
///
/// ## Key Features
/// - Automatic task cleanup on completion or cancellation
/// - Task identification and tracking by unique IDs
/// - Concurrent task execution with individual cancellation
/// - Error handling delegation to Store
///
/// ## Architecture Role
/// TaskManager is a core component of the Store's task execution system. It handles:
/// - Task lifecycle management (start, track, cancel, cleanup)
/// - Concurrent task coordination
/// - Memory safety through weak references
///
/// ## Usage
/// TaskManager is typically used internally by ``Store``. Tasks are automatically
/// cancelled when the TaskManager is deallocated (e.g., when Store is released).
/// ```swift
/// let taskManager = TaskManager()
///
/// // Execute a task with automatic tracking
/// taskManager.executeTask(
///   id: "fetchData",
///   operation: {
///     let data = try await api.fetchData()
///     print("Data loaded: \(data)")
///   },
///   onError: { error in
///     print("Failed: \(error)")
///   }
/// )
///
/// // Check if task is running
/// if taskManager.isTaskRunning(id: "fetchData") {
///   print("Task is still running")
/// }
///
/// // Tasks are automatically cancelled when taskManager is deallocated
/// ```
///
/// ## Task Lifecycle
/// 1. **Start**: Task is created and added to tracking dictionary
/// 2. **Execute**: Operation runs asynchronously on MainActor
/// 3. **Complete**: Task automatically removes itself from tracking
/// 4. **Error**: Error handler is called if provided
///
/// ## Memory Management
/// TaskManager uses weak references to prevent retain cycles and automatically
/// cleans up completed tasks using a deferred cleanup strategy.
///
/// ## Topics
/// ### Creating a Manager
/// - ``init()``
///
/// ### Task Execution
/// - ``executeTask(id:operation:onError:)``
///
/// ### Task Inspection
/// - ``isTaskRunning(id:)``
/// - ``runningTaskCount``
///
/// ### Internal Task Management
/// - ``cancelTaskInternal(id:)``
@MainActor
public final class TaskManager {
  nonisolated(unsafe) private var runningTasks: [String: Task<Void, Never>] = [:]

  /// Creates a new TaskManager instance.
  ///
  /// Initializes an empty task tracking dictionary ready to manage asynchronous operations.
  ///
  /// ## Example
  /// ```swift
  /// let taskManager = TaskManager()
  /// ```
  public init() {}

  /// Automatically cancels all running tasks when TaskManager is deallocated.
  ///
  /// This ensures proper resource cleanup when the Store (and its TaskManager)
  /// is released, such as when a View is dismissed or a feature scope ends.
  ///
  /// ## Design Rationale
  /// - **Automatic cleanup**: No manual cleanup required in View lifecycle
  /// - **Memory safety**: Prevents orphaned tasks from consuming resources
  /// - **Predictable behavior**: Task lifetime tied to Store lifetime
  ///
  /// ## Implementation Note
  /// Uses `nonisolated(unsafe)` on `runningTasks` to allow safe access during
  /// deinitialization. This is safe because:
  /// - `deinit` runs when the last reference is released
  /// - No other threads can access the instance at this point
  /// - Dictionary operations are isolated to this deinit block
  deinit {
    runningTasks.values.forEach { $0.cancel() }
    runningTasks.removeAll()
  }

  /// The number of currently running tasks.
  ///
  /// Use this property to monitor task activity.
  ///
  /// ## Example
  /// ```swift
  /// print("Active tasks: \(taskManager.runningTaskCount)")
  /// if taskManager.runningTaskCount > 10 {
  ///   print("Warning: Many concurrent tasks")
  /// }
  /// ```
  public var runningTaskCount: Int {
    runningTasks.count
  }

  /// Checks if a specific task is currently running.
  ///
  /// - Parameter id: The unique identifier for the task
  /// - Returns: `true` if the task is running, `false` otherwise
  ///
  /// ## Example
  /// ```swift
  /// if taskManager.isTaskRunning(id: "fetchUser") {
  ///   print("User fetch in progress")
  /// } else {
  ///   print("User fetch not started or completed")
  /// }
  /// ```
  public func isTaskRunning<ID: TaskID>(id: ID) -> Bool {
    let stringId = id.taskIdString
    return runningTasks[stringId] != nil
  }

  /// Executes an asynchronous operation as a tracked task and returns the Task.
  ///
  /// Creates and tracks a new task with automatic cleanup. If a task with the same
  /// ID already exists, the old task is cancelled before starting the new one.
  /// The task runs on the MainActor and handles errors through the provided handler.
  ///
  /// - Parameters:
  ///   - id: Unique identifier for the task (string representation)
  ///   - operation: The asynchronous operation to execute
  ///   - onError: Optional error handler called if the operation throws
  /// - Returns: The created Task that can be awaited for completion
  ///
  /// ## Example
  /// ```swift
  /// let task = taskManager.executeTask(
  ///   id: "loadProfile",
  ///   operation: {
  ///     let profile = try await api.fetchProfile()
  ///     await store.send(.profileLoaded(profile))
  ///   },
  ///   onError: { error in
  ///     await store.send(.profileLoadFailed(error))
  ///   }
  /// )
  ///
  /// // Optionally wait for completion
  /// await task.value
  /// ```
  ///
  /// - Note: Tasks automatically remove themselves from tracking upon completion
  @discardableResult
  public func executeTask(
    id: String,
    operation: @escaping () async throws -> Void,
    onError: ((Error) async -> Void)?
  ) -> Task<Void, Never> {
    if let existingTask = runningTasks[id] {
      existingTask.cancel()
      runningTasks.removeValue(forKey: id)
    }

    // Create task with automatic cleanup using defer
    let task = Task { @MainActor [weak self] in
      guard let self else { return }

      // Defer ensures cleanup happens exactly once, regardless of how the task completes
      // (normal completion, error, or cancellation)
      defer {
        runningTasks.removeValue(forKey: id)
      }

      do {
        try await operation()
      } catch {
        if let errorHandler = onError {
          await errorHandler(error)
        }
      }
    }

    runningTasks[id] = task
    return task
  }

  /// Internal method to cancel a task by string identifier.
  ///
  /// This method provides low-level task cancellation without generic type conversion.
  /// Used internally by ``Store`` when processing `.cancel(id:)` action tasks.
  ///
  /// - Parameter id: The string identifier of the task to cancel
  ///
  /// - Note: This is public for Store's internal use. Task cancellation should
  ///   be done through Actions (e.g., `return .cancel(id: "taskId")`), not by
  ///   calling this method directly.
  public func cancelTaskInternal(id: String) {
    runningTasks[id]?.cancel()
    runningTasks.removeValue(forKey: id)
  }
}
