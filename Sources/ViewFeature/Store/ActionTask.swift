import Foundation

/// Type constraint for task identifiers.
///
/// Task identifiers must be both `Hashable` (for dictionary lookup in TaskManager)
/// and `Sendable` (for Swift 6 concurrency safety).
///
/// ## Supported Types
/// You can use any type that conforms to both protocols:
/// - `String` - Most common: `"download"`, `"fetch-user"`
/// - `Int` - Simple numbering: `1`, `2`, `3`
/// - `UUID` - Guaranteed uniqueness
/// - Custom enums - Type-safe identifiers: `enum TaskID { case download, upload }`
///
/// ## Example
/// ```swift
/// // String
/// .run(id: "login") { }
///
/// // Int
/// .run(id: 42) { }
///
/// // UUID
/// .run(id: UUID()) { }
///
/// // Custom enum
/// enum MyTaskID: Hashable, Sendable {
///   case backgroundSync
///   case dataRefresh
/// }
/// .run(id: MyTaskID.backgroundSync) { }
/// ```
public typealias TaskID = Hashable & Sendable

/// Represents a task that can be returned from action processing.
///
/// `ActionTask` encapsulates asynchronous work that should be executed after
/// an action is processed. It provides a clean API for common patterns:
///
/// ## Basic Patterns
///
/// ### 1. Simple Async Task (90% of cases)
/// ```swift
/// return .run {
///   let data = try await api.fetch()
///   await store.send(.dataLoaded(data))
/// }
/// ```
///
/// ### 2. Cancellable Task
/// ```swift
/// return .run(id: "fetch") {
///   let data = try await longRunningOperation()
///   await store.send(.dataLoaded(data))
/// }
/// ```
///
/// Later, cancel it:
/// ```swift
/// return .cancel(id: "fetch")
/// ```
///
/// ### 3. Error Handling
/// ```swift
/// return .run {
///   try await riskyOperation()
/// }
/// .catch { error, state in
///   state.errorMessage = error.localizedDescription
///   state.isLoading = false
/// }
/// ```
///
/// ### 4. Cancellable + Error Handling
/// ```swift
/// return .run(id: "download") {
///   let file = try await downloader.download(url)
///   await store.send(.downloadComplete(file))
/// }
/// .catch { error, state in
///   state.isDownloading = false
///   state.errorMessage = "Download failed: \(error)"
/// }
/// ```
///
/// ## Topics
/// ### Creating Tasks
/// - ``none``
/// - ``run(operation:)``
/// - ``run(id:operation:)``
/// - ``cancel(id:)``
///
/// ### Error Handling
/// - ``catch(_:)``
public struct ActionTask<Action, State> {
    internal let storeTask: StoreTask<Action, State>
}

/// Generates unique task IDs using UUID
/// UUID-based IDs eliminate global state and enable safe parallel test execution
private enum TaskIdGenerator {
    static func generate() -> String {
        "auto-task-\(UUID().uuidString)"
    }
}

extension ActionTask {
    // MARK: - Factory Methods

    /// Returns a task that performs no asynchronous work.
    ///
    /// Use this when an action only modifies state synchronously without any side effects.
    ///
    /// ## Example
    /// ```swift
    /// case .increment:
    ///   state.count += 1
    ///   return .none
    /// ```
    public static var none: ActionTask {
        ActionTask(storeTask: .none)
    }

    /// Creates an asynchronous task with an automatically generated ID.
    ///
    /// The task will run but cannot be cancelled by ID. Use this for fire-and-forget
    /// operations that don't need user cancellation.
    ///
    /// - Parameter operation: The asynchronous operation to execute
    /// - Returns: An ActionTask that will execute the operation
    ///
    /// ## Example
    /// ```swift
    /// case .loadData:
    ///   state.isLoading = true
    ///   return .run {
    ///     let data = try await api.fetch()
    ///     await store.send(.dataLoaded(data))
    ///   }
    /// ```
    ///
    /// ## When to Use
    /// - Simple async operations that complete quickly
    /// - Operations that don't need user cancellation
    /// - Most common use case (90% of scenarios)
    ///
    /// ## When NOT to Use
    /// Use ``run(id:operation:)`` instead when:
    /// - User needs to cancel the operation (downloads, searches)
    /// - Long-running operations
    /// - You need to cancel on navigation/lifecycle events
    public static func run(
        operation: @escaping @MainActor (State) async throws -> Void
    ) -> ActionTask {
        let taskId = TaskIdGenerator.generate()
        return ActionTask(storeTask: .run(id: taskId, operation: operation, onError: nil))
    }

    /// Creates a cancellable asynchronous task with a specific ID.
    ///
    /// The task can be cancelled later using ``cancel(id:)`` with the same ID.
    /// This is useful for long-running operations that users might want to interrupt.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the task (can be any Hashable & Sendable type)
    ///   - operation: The asynchronous operation to execute
    /// - Returns: An ActionTask that will execute the operation
    ///
    /// ## Example: Long-Running Operation
    /// ```swift
    /// case .startDownload(let url):
    ///   state.isDownloading = true
    ///   return .run(id: "download") {
    ///     let file = try await downloader.download(url)
    ///     await store.send(.downloadComplete(file))
    ///   }
    ///
    /// case .cancelDownload:
    ///   state.isDownloading = false
    ///   return .cancel(id: "download")
    /// ```
    ///
    /// ## Example: Search Debouncing
    /// ```swift
    /// case .searchTextChanged(let text):
    ///   state.searchText = text
    ///   return .run(id: "search") {
    ///     try await Task.sleep(for: .milliseconds(300))
    ///     let results = try await api.search(text)
    ///     await store.send(.searchResults(results))
    ///   }
    ///   // Previous search is automatically cancelled
    /// ```
    ///
    /// ## ID Types
    /// You can use any ``TaskID`` type:
    /// ```swift
    /// .run(id: "my-task") { }           // String
    /// .run(id: 123) { }                  // Int
    /// .run(id: UUID()) { }               // UUID
    /// .run(id: TaskID.download) { }      // Custom enum
    /// ```
    ///
    /// ## Automatic Cancellation
    /// If you dispatch the same action multiple times, the previous task with
    /// the same ID is automatically cancelled before starting the new one.
    public static func run<ID: TaskID>(
        id: ID,
        operation: @escaping @MainActor (State) async throws -> Void
    ) -> ActionTask {
        let stringId = String(describing: id)
        return ActionTask(storeTask: .run(id: stringId, operation: operation, onError: nil))
    }

    /// Cancels a running task by its ID.
    ///
    /// If no task with the given ID is running, this does nothing.
    ///
    /// - Parameter id: The task identifier to cancel
    /// - Returns: An ActionTask that will cancel the specified task
    ///
    /// ## Example
    /// ```swift
    /// case .startOperation:
    ///   return .run(id: "operation") {
    ///     try await longOperation()
    ///   }
    ///
    /// case .cancelOperation:
    ///   return .cancel(id: "operation")
    /// ```
    ///
    /// ## Navigation Cleanup Example
    /// ```swift
    /// case .viewDidDisappear:
    ///   return .cancel(id: "background-sync")
    /// ```
    ///
    /// ## Multiple Cancellations
    /// You can cancel multiple tasks in one action using ``Store/cancelAllTasks()``
    /// or by sending multiple cancel actions:
    /// ```swift
    /// case .cleanupAll:
    ///   await store.send(.cancel(id: "task1"))
    ///   await store.send(.cancel(id: "task2"))
    ///   return .none
    /// ```
    public static func cancel<ID: TaskID>(id: ID) -> ActionTask {
        let stringId = String(describing: id)
        return ActionTask(storeTask: .cancel(id: stringId))
    }

    // MARK: - Method Chaining

    /// Adds error handling to the task.
    ///
    /// The error handler is called if the task's operation throws an error.
    /// It receives both the error and an `inout` state parameter, allowing you
    /// to update the state based on the error.
    ///
    /// - Parameter handler: A closure that handles errors
    /// - Returns: A new ActionTask with error handling
    ///
    /// ## Example: Basic Error Handling
    /// ```swift
    /// return .run {
    ///   try await riskyOperation()
    /// }
    /// .catch { error, state in
    ///   state.errorMessage = error.localizedDescription
    ///   state.isLoading = false
    /// }
    /// ```
    ///
    /// ## Example: Error Type Differentiation
    /// ```swift
    /// return .run(id: "login") {
    ///   try await auth.login(credentials)
    /// }
    /// .catch { error, state in
    ///   switch error {
    ///   case AuthError.invalidCredentials:
    ///     state.errorMessage = "Invalid username or password"
    ///   case AuthError.networkError:
    ///     state.errorMessage = "Network connection failed"
    ///   default:
    ///     state.errorMessage = "An unexpected error occurred"
    ///   }
    ///   state.isLoading = false
    /// }
    /// ```
    ///
    /// ## Example: Retry Logic
    /// ```swift
    /// return .run(id: "fetch") {
    ///   try await api.fetch()
    /// }
    /// .catch { error, state in
    ///   state.retryCount += 1
    ///   if state.retryCount < 3 {
    ///     // Will be retried by dispatching the same action
    ///     state.shouldRetry = true
    ///   } else {
    ///     state.errorMessage = "Failed after 3 attempts"
    ///   }
    /// }
    /// ```
    ///
    /// ## With Cancellable Tasks
    /// ```swift
    /// return .run(id: "download") {
    ///   let file = try await downloader.download(url)
    ///   await store.send(.downloadComplete(file))
    /// }
    /// .catch { error, state in
    ///   state.isDownloading = false
    ///   state.downloadError = error.localizedDescription
    /// }
    /// ```
    ///
    /// - Note: The error handler runs on the MainActor and can safely mutate state
    public func `catch`(_ handler: @escaping @MainActor (Error, State) -> Void) -> ActionTask {
        switch storeTask {
        case .run(let id, let operation, _):
            return ActionTask(storeTask: .run(id: id, operation: operation, onError: handler))
        default:
            return self
        }
    }
}
