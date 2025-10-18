import Foundation
import Synchronization

// MARK: - TaskID Protocol

/// Protocol for types that can be converted to task ID strings.
public protocol TaskIDConvertible: Hashable, Sendable {
    /// Converts the task ID to a string representation.
    var taskIdString: String { get }
}

/// Default implementations for common types
extension String: TaskIDConvertible {
    public var taskIdString: String { self }
}

extension Int: TaskIDConvertible {
    public var taskIdString: String { String(self) }
}

extension UUID: TaskIDConvertible {
    public var taskIdString: String { uuidString }
}

/// Default implementation for CustomStringConvertible types
extension TaskIDConvertible where Self: CustomStringConvertible {
    public var taskIdString: String { description }
}

/// Default implementation for RawRepresentable types (enums with String raw value)
extension TaskIDConvertible where Self: RawRepresentable, RawValue == String {
    public var taskIdString: String { rawValue }
}

/// Task identifiers (String, Int, UUID, or custom enums).
public typealias TaskID = TaskIDConvertible

// MARK: - TaskID Generator

/// Generates unique task IDs using atomic counter
/// Atomic counter-based IDs are faster than UUID and still enable safe parallel test execution
private enum TaskIdGenerator {
    private static let counter = Atomic<UInt64>(0)

    static func generate() -> String {
        // .relaxed is safe: only atomicity (uniqueness) required, no memory ordering needed.
        // ID generation is independent of other memory operations, and TaskManager uses @MainActor
        // for synchronization. Stronger orderings (.acquiring, .sequentiallyConsistent) would add
        // unnecessary performance cost without providing useful guarantees.
        let id = counter.wrappingAdd(1, ordering: .relaxed)
        return "auto-task-\(id)"
    }
}

// MARK: - ActionTask

/// Represents asynchronous work returned from action processing.
///
/// `ActionTask` provides a composable, type-safe way to express asynchronous side effects
/// in your application. All task operations execute on the **MainActor**, ensuring thread-safe
/// state access and seamless SwiftUI integration.
///
/// ## Core Operations
///
/// **Creating Tasks:**
/// ```swift
/// // Simple asynchronous task
/// return .run { state in
///   let data = try await api.fetch()
///   state.data = data  // ✅ Safe MainActor mutation
/// }
///
/// // Cancellable task
/// return .run { state in
///   let data = try await api.fetch()
///   state.data = data
/// }
/// .cancellable(id: "fetch", cancelInFlight: true)
///
/// // With error handling
/// return .run { state in
///   let data = try await api.fetch()
///   state.data = data
/// }
/// .catch { error, state in
///   state.errorMessage = "\(error)"
/// }
/// ```
///
/// **Cancelling Tasks:**
/// ```swift
/// // Cancel a single task
/// return .cancel(id: "fetch")
///
/// // Cancel multiple tasks
/// return .cancel(ids: ["fetch-1", "fetch-2"])
/// ```
///
/// ## Task Composition
///
/// ActionTask supports powerful composition operations following functional programming principles:
///
/// **Parallel Execution (merge):**
/// ```swift
/// // Multiple API calls running concurrently
/// return .merge(
///     .run { state in
///         state.users = try await api.fetchUsers()
///     },
///     .run { state in
///         state.posts = try await api.fetchPosts()
///     },
///     .run { state in
///         state.comments = try await api.fetchComments()
///     }
/// )
/// ```
///
/// **Sequential Execution (concatenate):**
/// ```swift
/// // Step-by-step workflow
/// return .concatenate(
///     .run { state in
///         state.step = 1
///         try await Task.sleep(for: .seconds(1))
///     },
///     .run { state in
///         state.step = 2
///         try await Task.sleep(for: .seconds(1))
///     },
///     .run { state in
///         state.step = 3
///     }
/// )
/// ```
///
/// **Nested Composition:**
/// ```swift
/// // Complex workflow combining parallel and sequential execution
/// return .concatenate(
///     // Step 1: Initialize
///     .run { state in state.loading = true },
///
///     // Step 2: Fetch data in parallel
///     .merge(
///         .run { state in
///             state.profile = try await api.fetchProfile()
///         },
///         .run { state in
///             state.settings = try await api.fetchSettings()
///         }
///     ),
///
///     // Step 3: Finalize
///     .run { state in state.loading = false }
/// )
/// ```
///
/// ## Mathematical Properties
///
/// ActionTask composition follows Monoid laws:
/// - **Identity**: `.merge(.none, task) == task`
/// - **Associativity**: `.merge(a, .merge(b, c)) == .merge(.merge(a, b), c)`
///
/// This ensures predictable and composable behavior.
///
/// ## Topics
/// ### Creating Tasks
/// - ``none``
/// - ``run(operation:)``
/// - ``cancel(id:)``
/// - ``cancel(ids:)``
///
/// ### Composing Tasks
/// - ``merge(_:)-static``
/// - ``merge(_:)-array``
/// - ``concatenate(_:)-static``
/// - ``concatenate(_:)-array``
///
/// ### Configuring Tasks
/// - ``catch(_:)``
/// - ``cancellable(id:cancelInFlight:)``
/// - ``priority(_:)``
public struct ActionTask<Action, State> {
    // MARK: - Internal Operation Type

    /// Internal representation of task operations.
    ///
    /// This enum uses `indirect` cases for composition operations to support
    /// recursive task structures (tasks containing other tasks).
    internal enum Operation {
        /// No operation to perform
        case none

        /// Execute an asynchronous operation
        case run(
            id: String,
            operation: @MainActor (State) async throws -> Void,
            onError: (@MainActor (Error, State) -> Void)?,
            cancelInFlight: Bool,
            priority: TaskPriority?
        )

        /// Cancel running tasks by their IDs
        case cancels(ids: [String])

        /// Merge two tasks to run in parallel
        /// Uses `indirect` to support recursive composition
        indirect case merged(ActionTask, ActionTask)

        /// Concatenate two tasks to run sequentially
        /// Uses `indirect` to support recursive composition
        indirect case concatenated(ActionTask, ActionTask)
    }

    internal let operation: Operation

    /// Internal initializer
    private init(operation: Operation) {
        self.operation = operation
    }
}

// MARK: - Factory Methods

extension ActionTask {
    /// Returns a task that performs no asynchronous work.
    ///
    /// This is the identity element for task composition:
    /// - `.merge(.none, task)` returns `task`
    /// - `.concatenate(.none, task)` returns `task`
    ///
    /// ## Example
    /// ```swift
    /// // Conditional task execution
    /// return shouldFetch ? .run { ... } : .none
    /// ```
    public static var none: ActionTask {
        ActionTask(operation: .none)
    }

    /// Creates an asynchronous task with an automatically generated ID.
    ///
    /// The task executes on the MainActor, allowing safe state mutations.
    /// Use `.cancellable(id:cancelInFlight:)` to make the task cancellable by a specific ID.
    ///
    /// ## Example
    /// ```swift
    /// // Simple task without cancellation
    /// return .run { state in
    ///   let data = try await fetch()
    ///   state.data = data
    /// }
    ///
    /// // Make it cancellable with ID
    /// return .run { state in
    ///   let data = try await fetch()
    ///   state.data = data
    /// }
    /// .cancellable(id: "fetch", cancelInFlight: true)
    /// ```
    ///
    /// - Parameter operation: The async operation to execute, receiving mutable state
    /// - Returns: A new `ActionTask` that will execute the operation
    public static func run(
        operation: @escaping @MainActor (State) async throws -> Void
    ) -> ActionTask {
        let taskId = TaskIdGenerator.generate()
        return ActionTask(operation: .run(
            id: taskId,
            operation: operation,
            onError: nil,
            cancelInFlight: false,
            priority: nil
        ))
    }

    /// Cancels a running task by its ID.
    ///
    /// If the task isn't running, this operation does nothing.
    ///
    /// ## Example
    /// ```swift
    /// case .cancelFetch:
    ///   return .cancel(id: "fetch")
    /// ```
    ///
    /// - Parameter id: The identifier of the task to cancel
    /// - Returns: A new `ActionTask` that will cancel the specified task
    public static func cancel<ID: TaskID>(id: ID) -> ActionTask {
        let stringId = id.taskIdString
        return ActionTask(operation: .cancels(ids: [stringId]))
    }

    /// Cancels multiple running tasks by their IDs.
    ///
    /// Tasks that aren't running are ignored. This is useful for cancelling
    /// a group of related tasks at once.
    ///
    /// ## Example
    /// ```swift
    /// // Cancel all download tasks
    /// return .cancel(ids: ["download-1", "download-2", "download-3"])
    ///
    /// // Cancel tasks from an array
    /// let taskIds = state.activeDownloads.map(\.id)
    /// return .cancel(ids: taskIds)
    /// ```
    ///
    /// - Parameter ids: An array of task identifiers to cancel
    /// - Returns: A new `ActionTask` that will cancel the specified tasks
    public static func cancel<ID: TaskID>(ids: [ID]) -> ActionTask {
        let stringIds = ids.map { $0.taskIdString }
        return ActionTask(operation: .cancels(ids: stringIds))
    }
}

// MARK: - Composition Methods

extension ActionTask {
    /// Merges multiple tasks to run in parallel.
    ///
    /// All tasks execute concurrently using Swift's structured concurrency.
    /// The merged task completes when all child tasks complete.
    ///
    /// ## Mathematical Properties
    /// Merge follows Monoid laws:
    /// - **Identity**: `.merge(.none, task) == task`
    /// - **Associativity**: `.merge(a, .merge(b, c)) == .merge(.merge(a, b), c)`
    ///
    /// ## Example
    /// ```swift
    /// // Fetch multiple resources concurrently
    /// return .merge(
    ///     .run { state in
    ///         state.users = try await api.fetchUsers()
    ///     },
    ///     .run { state in
    ///         state.posts = try await api.fetchPosts()
    ///     },
    ///     .run { state in
    ///         state.comments = try await api.fetchComments()
    ///     }
    /// )
    /// ```
    ///
    /// - Parameter tasks: Variadic list of tasks to merge
    /// - Returns: A single task that runs all tasks in parallel
    public static func merge(_ tasks: ActionTask...) -> ActionTask {
        merge(tasks)
    }

    /// Merges an array of tasks to run in parallel.
    ///
    /// This is the array version of the variadic `merge` method.
    /// Useful when you have a dynamic number of tasks.
    ///
    /// ## Example
    /// ```swift
    /// // Fetch data for each user ID
    /// let fetchTasks = userIDs.map { id in
    ///     ActionTask.run { state in
    ///         state.users[id] = try await api.fetchUser(id: id)
    ///     }
    /// }
    /// return .merge(fetchTasks)
    /// ```
    ///
    /// - Parameter tasks: Array of tasks to merge
    /// - Returns: A single task that runs all tasks in parallel
    public static func merge(_ tasks: [ActionTask]) -> ActionTask {
        // TCA-style reduce pattern implementing Monoid
        tasks.reduce(.none) { $0.merge(with: $1) }
    }

    /// Concatenates multiple tasks to run sequentially.
    ///
    /// Tasks execute one after another in order. Each task starts only
    /// after the previous one completes.
    ///
    /// ## Mathematical Properties
    /// Concatenate follows Monoid laws:
    /// - **Identity**: `.concatenate(.none, task) == task`
    /// - **Associativity**: `.concatenate(a, .concatenate(b, c)) == .concatenate(.concatenate(a, b), c)`
    ///
    /// ## Example
    /// ```swift
    /// // Multi-step workflow
    /// return .concatenate(
    ///     .run { state in
    ///         state.step = 1
    ///         try await Task.sleep(for: .seconds(1))
    ///     },
    ///     .run { state in
    ///         state.step = 2
    ///         try await Task.sleep(for: .seconds(1))
    ///     },
    ///     .run { state in
    ///         state.step = 3
    ///     }
    /// )
    /// ```
    ///
    /// - Parameter tasks: Variadic list of tasks to concatenate
    /// - Returns: A single task that runs all tasks sequentially
    public static func concatenate(_ tasks: ActionTask...) -> ActionTask {
        concatenate(tasks)
    }

    /// Concatenates an array of tasks to run sequentially.
    ///
    /// This is the array version of the variadic `concatenate` method.
    /// Useful when you have a dynamic number of tasks.
    ///
    /// ## Example
    /// ```swift
    /// // Process items one by one
    /// let processTasks = items.map { item in
    ///     ActionTask.run { state in
    ///         state.processed.append(try await process(item))
    ///     }
    /// }
    /// return .concatenate(processTasks)
    /// ```
    ///
    /// - Parameter tasks: Array of tasks to concatenate
    /// - Returns: A single task that runs all tasks sequentially
    public static func concatenate(_ tasks: [ActionTask]) -> ActionTask {
        // TCA-style reduce pattern implementing Monoid
        tasks.reduce(.none) { $0.concatenate(with: $1) }
    }

    // MARK: - Internal Binary Operations

    /// Internal method to merge this task with another.
    ///
    /// Implements the Monoid identity law: `.merge(.none, task) == task`
    internal func merge(with other: ActionTask) -> ActionTask {
        switch (self.operation, other.operation) {
        case (.none, _):
            // Identity: .none is left identity
            return other
        case (_, .none):
            // Identity: .none is right identity
            return self
        default:
            // Create merged task for all other cases
            return ActionTask(operation: .merged(self, other))
        }
    }

    /// Internal method to concatenate this task with another.
    ///
    /// Implements the Monoid identity law: `.concatenate(.none, task) == task`
    internal func concatenate(with other: ActionTask) -> ActionTask {
        switch (self.operation, other.operation) {
        case (.none, _):
            // Identity: .none is left identity
            return other
        case (_, .none):
            // Identity: .none is right identity
            return self
        default:
            // Create concatenated task for all other cases
            return ActionTask(operation: .concatenated(self, other))
        }
    }
}

// MARK: - Configuration Methods

extension ActionTask {
    /// Adds error handling to the task.
    ///
    /// The error handler receives both the error and mutable state,
    /// allowing you to update state in response to errors.
    ///
    /// ## Example
    /// ```swift
    /// return .run { state in
    ///   let result = try await riskyOperation()
    ///   state.result = result
    /// }
    /// .catch { error, state in
    ///   state.errorMessage = error.localizedDescription
    ///   state.hasError = true
    /// }
    /// ```
    ///
    /// - Parameter handler: Error handler that receives the error and mutable state
    /// - Returns: A new `ActionTask` with the error handler attached
    ///
    /// - Note: Only affects `.run` tasks. Has no effect on other task types.
    public func `catch`(_ handler: @escaping @MainActor (Error, State) -> Void) -> ActionTask {
        switch operation {
        case .run(let id, let op, _, let cancelInFlight, let priority):
            return ActionTask(operation: .run(
                id: id,
                operation: op,
                onError: handler,
                cancelInFlight: cancelInFlight,
                priority: priority
            ))
        default:
            return self
        }
    }

    /// Makes this task cancellable with a specific ID.
    ///
    /// This method allows you to:
    /// 1. Assign a specific ID to the task (overriding any auto-generated ID)
    /// 2. Optionally cancel any in-flight task with the same ID before starting this one
    ///
    /// ## Examples
    /// ```swift
    /// // Cancel previous search before starting new one
    /// return .run { state in
    ///   let results = try await search(state.query)
    ///   state.results = results
    /// }
    /// .cancellable(id: "search", cancelInFlight: true)
    ///
    /// // Multiple downloads can run concurrently
    /// return .run { state in
    ///   let data = try await download(url)
    ///   state.downloads[url] = data
    /// }
    /// .cancellable(id: "download-\(url)", cancelInFlight: false)
    /// ```
    ///
    /// - Parameters:
    ///   - id: The identifier for this task
    ///   - cancelInFlight: If `true`, cancels any running task with the same ID before starting this one.
    ///                     If `false` (default), allows multiple tasks with the same ID to run concurrently.
    /// - Returns: A new `ActionTask` with the specified ID and cancellation behavior
    ///
    /// - Note: Only affects `.run` tasks. Has no effect on other task types.
    public func cancellable<ID: TaskID>(
        id: ID,
        cancelInFlight: Bool = false
    ) -> ActionTask {
        switch operation {
        case .run(_, let op, let onError, _, let priority):
            let stringId = id.taskIdString
            return ActionTask(operation: .run(
                id: stringId,
                operation: op,
                onError: onError,
                cancelInFlight: cancelInFlight,
                priority: priority
            ))
        default:
            return self
        }
    }

    /// Sets the priority for this task.
    ///
    /// Task priority determines the scheduling order. Use higher priorities
    /// for user-facing operations and lower priorities for background work.
    ///
    /// ## Examples
    /// ```swift
    /// // High priority for critical user-facing operations
    /// return .run { state in
    ///   let data = try await api.fetchCritical()
    ///   state.data = data
    /// }
    /// .priority(.high)
    ///
    /// // Background priority for non-urgent work
    /// return .run { state in
    ///   try await analytics.upload()
    /// }
    /// .priority(.background)
    ///
    /// // Combine with other methods
    /// return .run { state in
    ///   let user = try await api.fetchUser()
    ///   state.user = user
    /// }
    /// .priority(.userInitiated)
    /// .cancellable(id: "loadUser", cancelInFlight: true)
    /// .catch { error, state in
    ///   state.errorMessage = "\(error)"
    /// }
    /// ```
    ///
    /// - Parameter priority: The task priority level
    /// - Returns: A new `ActionTask` with the specified priority
    ///
    /// - Note: Only affects `.run` tasks. Has no effect on other task types.
    public func priority(_ priority: TaskPriority) -> ActionTask {
        switch operation {
        case .run(let id, let op, let onError, let cancelInFlight, _):
            return ActionTask(operation: .run(
                id: id,
                operation: op,
                onError: onError,
                cancelInFlight: cancelInFlight,
                priority: priority
            ))
        default:
            return self
        }
    }
}
