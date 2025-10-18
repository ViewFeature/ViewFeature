import Foundation
import Synchronization

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

/// Represents asynchronous work returned from action processing.
///
/// ```swift
/// // Simple task
/// return .run { state in
///   let data = try await api.fetch()
///   state.data = data
/// }
///
/// // Cancellable task
/// return .run { state in
///   let data = try await api.fetch()
///   state.data = data
///   state.isLoading = false
/// }
/// .cancellable(id: "fetch")
///
/// // Cancel task(s)
/// return .cancel(id: "fetch")
/// return .cancel(ids: ["fetch-1", "fetch-2"])
///
/// // With error handling
/// return .run { state in
///   let data = try await api.fetch()
///   state.data = data
/// }
/// .catch { error, state in state.errorMessage = "\(error)" }
/// ```
public struct ActionTask<Action, State> {
  internal let storeTask: StoreTask<Action, State>
}

/// Generates unique task IDs using atomic counter
/// Atomic counter-based IDs are faster than UUID and still enable safe parallel test execution
private enum TaskIdGenerator {
  private static let counter = Atomic<UInt64>(0)

  static func generate() -> String {
    let id = counter.wrappingAdd(1, ordering: .relaxed)
    return "auto-task-\(id)"
  }
}

extension ActionTask {
  // MARK: - Factory Methods

  /// Returns a task that performs no asynchronous work.
  public static var none: ActionTask {
    ActionTask(storeTask: .none)
  }

  /// Creates an asynchronous task with an automatically generated ID.
  ///
  /// Use `.cancellable(id:cancelInFlight:)` to make the task cancellable by ID.
  ///
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
  public static func run(
    operation: @escaping @MainActor (State) async throws -> Void
  ) -> ActionTask {
    let taskId = TaskIdGenerator.generate()
    return ActionTask(storeTask: .run(id: taskId, operation: operation, onError: nil, cancelInFlight: false))
  }

  /// Cancels a running task by its ID. Does nothing if the task isn't running.
  ///
  /// ```swift
  /// return .cancel(id: "fetch")
  /// ```
  public static func cancel<ID: TaskID>(id: ID) -> ActionTask {
    let stringId = id.taskIdString
    return ActionTask(storeTask: .cancels(ids: [stringId]))
  }

  /// Cancels multiple running tasks by their IDs. Does nothing for tasks that aren't running.
  ///
  /// This is useful when you need to cancel a group of related tasks at once:
  ///
  /// ```swift
  /// // Cancel all download tasks
  /// return .cancel(ids: ["download-1", "download-2", "download-3"])
  ///
  /// // Cancel all tasks with IDs from an array
  /// let taskIds = ["task-a", "task-b", "task-c"]
  /// return .cancel(ids: taskIds)
  /// ```
  ///
  /// - Parameter ids: An array of task identifiers to cancel
  public static func cancel<ID: TaskID>(ids: [ID]) -> ActionTask {
    let stringIds = ids.map { $0.taskIdString }
    return ActionTask(storeTask: .cancels(ids: stringIds))
  }

  // MARK: - Method Chaining

  /// Adds error handling to the task.
  ///
  /// ```swift
  /// return .run { state in
  ///   let result = try await riskyOperation()
  ///   state.result = result
  /// }
  /// .catch { error, state in
  ///   state.errorMessage = error.localizedDescription
  /// }
  /// ```
  public func `catch`(_ handler: @escaping @MainActor (Error, State) -> Void) -> ActionTask {
    switch storeTask {
    case .run(let id, let operation, _, let cancelInFlight):
      return ActionTask(storeTask: .run(id: id, operation: operation, onError: handler, cancelInFlight: cancelInFlight))
    default:
      return self
    }
  }

  /// Makes this task cancellable with a specific ID and optional automatic cancellation.
  ///
  /// This method allows you to:
  /// 1. Assign a specific ID to the task (overriding any auto-generated ID)
  /// 2. Optionally cancel any in-flight task with the same ID before starting this one
  ///
  /// ```swift
  /// // Cancel previous search before starting new one
  /// return .run { state in
  ///   let results = try await search(text)
  ///   state.results = results
  /// }
  /// .cancellable(id: "search", cancelInFlight: true)
  ///
  /// // Multiple downloads can run concurrently (cancelInFlight: false)
  /// return .run { state in
  ///   let data = try await download(url)
  ///   state.downloads[url] = data
  /// }
  /// .cancellable(id: "download-\(url)", cancelInFlight: false)
  /// ```
  ///
  /// - Parameters:
  ///   - id: The identifier for this task. Can be any `TaskID` type (String, Int, UUID, or custom enum).
  ///   - cancelInFlight: If `true`, cancels any running task with the same ID before starting this one.
  ///                     If `false` (default), allows multiple tasks with the same ID to run concurrently.
  /// - Returns: A new `ActionTask` with the specified ID and cancellation behavior.
  ///
  /// - Note: This method only affects `.run` tasks. It has no effect on `.none` or `.cancel` tasks.
  public func cancellable<ID: TaskID>(
    id: ID,
    cancelInFlight: Bool = false
  ) -> ActionTask {
    switch storeTask {
    case .run(_, let operation, let onError, _):
      let stringId = id.taskIdString
      return ActionTask(storeTask: .run(
        id: stringId,
        operation: operation,
        onError: onError,
        cancelInFlight: cancelInFlight
      ))
    default:
      return self
    }
  }
}
