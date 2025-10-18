import Foundation

/// Protocol for executing and managing asynchronous tasks.
///
/// `TaskExecuting` provides an abstraction over task execution and lifecycle management,
/// enabling test doubles and alternative implementations while maintaining the same interface.
/// This follows the Dependency Inversion Principle (DIP) by depending on an abstraction
/// rather than a concrete implementation.
///
/// ## Purpose
///
/// This protocol exists primarily to improve **testability**. By abstracting task execution,
/// tests can use simplified implementations (like `ImmediateTaskManager`) that execute
/// tasks synchronously and deterministically, avoiding flaky tests and reducing test duration.
///
/// ## Default Implementation
///
/// The production implementation is ``TaskManager``, which provides full asynchronous task
/// execution with proper lifecycle management, cancellation, and MainActor isolation.
///
/// ## Testing
///
/// For tests, use `ImmediateTaskManager` (from ViewFeatureTestSupport) which:
/// - Executes tasks immediately and synchronously
/// - Tracks all executed and cancelled tasks
/// - Provides assertions for task execution
/// - Eliminates timing issues in tests
///
/// ## Example
///
/// ```swift
/// // Production code
/// let store = Store(
///     initialState: MyFeature.State(),
///     feature: MyFeature()
///     // Uses TaskManager by default
/// )
///
/// // Test code
/// let taskExecutor = ImmediateTaskManager()
/// let store = Store(
///     initialState: MyFeature.State(),
///     feature: MyFeature(),
///     taskExecutor: taskExecutor
/// )
///
/// await store.send(.loadData).value
/// taskExecutor.assertTaskExecuted(id: "load-data")
/// ```
///
/// ## Topics
///
/// ### Task Execution
/// - ``executeTask(id:operation:onError:)``
///
/// ### Task Cancellation
/// - ``cancelTasks(ids:)``
///
/// ### Task Inspection
/// - ``runningTaskCount``
/// - ``isTaskRunning(id:)``
@MainActor
public protocol TaskExecuting {
    /// Executes an asynchronous operation as a tracked task.
    ///
    /// Creates and tracks a new task with automatic cleanup. The task runs on the MainActor
    /// and handles errors through the provided handler.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the task (string representation)
    ///   - operation: The asynchronous operation to execute
    ///   - onError: Optional error handler called if the operation throws
    /// - Returns: The created Task that can be awaited for completion
    ///
    /// ## Behavior
    ///
    /// - Tasks automatically remove themselves from tracking upon completion
    /// - If a task with the same ID already exists, implementations may choose to
    ///   cancel it before starting the new one (implementation-defined)
    /// - The task executes on the MainActor
    ///
    /// ## Example
    ///
    /// ```swift
    /// let task = taskExecutor.executeTask(
    ///     id: "loadProfile",
    ///     operation: {
    ///         let profile = try await api.fetchProfile()
    ///         state.profile = profile
    ///     },
    ///     onError: { error in
    ///         state.errorMessage = "Failed to load profile"
    ///     }
    /// )
    ///
    /// // Optionally wait for completion
    /// await task.value
    /// ```
    @discardableResult
    func executeTask(
        id: String,
        operation: @escaping () async throws -> Void,
        onError: ((Error) async -> Void)?
    ) -> Task<Void, Never>

    /// Cancels multiple tasks by their string identifiers.
    ///
    /// This method provides task cancellation for the Store's internal use.
    /// Tasks that are not currently running are silently ignored.
    ///
    /// - Parameter ids: The string identifiers of the tasks to cancel
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Cancel all download tasks
    /// taskExecutor.cancelTasks(ids: ["download-1", "download-2", "download-3"])
    /// ```
    ///
    /// - Note: In your action handlers, prefer using `ActionTask.cancel(ids:)`
    ///   rather than calling this method directly.
    func cancelTasks(ids: [String])

    /// The number of currently running tasks.
    ///
    /// Use this property to monitor task activity for debugging or UI purposes.
    ///
    /// ## Example
    ///
    /// ```swift
    /// if taskExecutor.runningTaskCount > 10 {
    ///     print("Warning: Many concurrent tasks")
    /// }
    /// ```
    var runningTaskCount: Int { get }

    /// Checks if a specific task is currently running.
    ///
    /// - Parameter id: The unique identifier for the task
    /// - Returns: `true` if the task is running, `false` otherwise
    ///
    /// ## Example
    ///
    /// ```swift
    /// if taskExecutor.isTaskRunning(id: "fetchUser") {
    ///     print("User fetch in progress")
    /// }
    /// ```
    func isTaskRunning<ID: TaskID>(id: ID) -> Bool
}
