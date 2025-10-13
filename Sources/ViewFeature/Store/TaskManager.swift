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
/// TaskManager is typically used internally by ``Store`` but can be used independently:
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
/// // Cancel specific task
/// taskManager.cancelTask(id: "fetchData")
///
/// // Cancel all running tasks
/// taskManager.cancelAllTasks()
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
/// ### Task Cancellation
/// - ``cancelTask(id:)``
/// - ``cancelAllTasks()``
/// - ``cancelTaskInternal(id:)``
@MainActor
public final class TaskManager {
  private var runningTasks: [String: Task<Void, Never>] = [:]

  /// Creates a new TaskManager instance.
  ///
  /// Initializes an empty task tracking dictionary ready to manage asynchronous operations.
  ///
  /// ## Example
  /// ```swift
  /// let taskManager = TaskManager()
  /// ```
  public init() {}

  /// The number of currently running tasks.
  ///
  /// Use this property to monitor task activity and prevent resource exhaustion.
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
    let stringId = String(describing: id)
    return runningTasks[stringId] != nil
  }

  /// Cancels a specific running task by its identifier.
  ///
  /// If the task is found, it will be cancelled and removed from tracking.
  /// If the task doesn't exist or has already completed, this method does nothing.
  ///
  /// - Parameter id: The unique identifier for the task to cancel
  ///
  /// ## Example
  /// ```swift
  /// // Start a long-running task
  /// taskManager.executeTask(id: "uploadFile", operation: { /* ... */ })
  ///
  /// // Cancel it if user navigates away
  /// taskManager.cancelTask(id: "uploadFile")
  /// ```
  public func cancelTask<ID: TaskID>(id: ID) {
    let stringId = String(describing: id)
    cancelTaskInternal(id: stringId)
  }

  /// Cancels all currently running tasks.
  ///
  /// This method iterates through all tracked tasks, cancels them, and clears
  /// the tracking dictionary. Useful for cleanup when a feature is dismissed or
  /// the app enters the background.
  ///
  /// ## Example
  /// ```swift
  /// // Cancel all tasks when view disappears
  /// func viewDidDisappear() {
  ///   taskManager.cancelAllTasks()
  /// }
  /// ```
  public func cancelAllTasks() {
    runningTasks.values.forEach { $0.cancel() }
    runningTasks.removeAll()
  }

  /// Executes an asynchronous operation as a tracked task.
  ///
  /// Creates and tracks a new task with automatic cleanup. If a task with the same
  /// ID already exists, the old task is cancelled before starting the new one.
  /// The task runs on the MainActor and handles errors through the provided handler.
  ///
  /// - Parameters:
  ///   - id: Unique identifier for the task (string representation)
  ///   - operation: The asynchronous operation to execute
  ///   - onError: Optional error handler called if the operation throws
  ///
  /// ## Example
  /// ```swift
  /// taskManager.executeTask(
  ///   id: "loadProfile",
  ///   operation: {
  ///     let profile = try await api.fetchProfile()
  ///     await store.send(.profileLoaded(profile))
  ///   },
  ///   onError: { error in
  ///     await store.send(.profileLoadFailed(error))
  ///   }
  /// )
  /// ```
  ///
  /// - Note: Tasks automatically remove themselves from tracking upon completion
  public func executeTask(
    id: String,
    operation: @escaping () async throws -> Void,
    onError: ((Error) async -> Void)?
  ) {
    if let existingTask = runningTasks[id] {
      existingTask.cancel()
      runningTasks.removeValue(forKey: id)
    }

    // Create task with automatic cleanup on completion
    runningTasks[id] = Task { [weak self] in
      defer {
        // Automatically remove completed task from tracking
        self?.runningTasks.removeValue(forKey: id)
      }

      do {
        try await operation()
      } catch {
        if let errorHandler = onError {
          await errorHandler(error)
        }
      }
    }
  }

  /// Internal method to cancel a task by string identifier.
  ///
  /// This method provides low-level task cancellation without generic type conversion.
  /// Used internally by ``cancelTask(id:)`` and by ``Store`` for direct task management.
  ///
  /// - Parameter id: The string identifier of the task to cancel
  ///
  /// - Note: This is public for Store's internal use but typically shouldn't be called directly
  public func cancelTaskInternal(id: String) {
    runningTasks[id]?.cancel()
    runningTasks.removeValue(forKey: id)
  }
}
