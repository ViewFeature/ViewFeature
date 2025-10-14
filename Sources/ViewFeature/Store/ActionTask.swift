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
/// return .run { try await api.fetch() }
///
/// // Cancellable task
/// return .run(id: "fetch") { try await api.fetch() }
/// return .cancel(id: "fetch")
///
/// // With error handling
/// return .run { try await api.fetch() }
///   .catch { error, state in state.errorMessage = "\(error)" }
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
  /// Cannot be cancelled by ID. For cancellable tasks, use `run(id:operation:)`.
  public static func run(
    operation: @escaping @MainActor (State) async throws -> Void
  ) -> ActionTask {
    let taskId = TaskIdGenerator.generate()
    return ActionTask(storeTask: .run(id: taskId, operation: operation, onError: nil))
  }

  /// Creates a cancellable task with a specific ID.
  ///
  /// Can be cancelled later using `cancel(id:)`. Tasks with the same ID automatically cancel previous instances.
  ///
  /// ```swift
  /// return .run(id: "download") { try await download() }
  /// // Later: return .cancel(id: "download")
  /// ```
  public static func run<ID: TaskID>(
    id: ID,
    operation: @escaping @MainActor (State) async throws -> Void
  ) -> ActionTask {
    let stringId = id.taskIdString
    return ActionTask(storeTask: .run(id: stringId, operation: operation, onError: nil))
  }

  /// Cancels a running task by its ID. Does nothing if the task isn't running.
  public static func cancel<ID: TaskID>(id: ID) -> ActionTask {
    let stringId = id.taskIdString
    return ActionTask(storeTask: .cancel(id: stringId))
  }

  // MARK: - Method Chaining

  /// Adds error handling to the task.
  ///
  /// ```swift
  /// return .run { try await riskyOperation() }
  ///   .catch { error, state in
  ///     state.errorMessage = error.localizedDescription
  ///   }
  /// ```
  public func `catch`(_ handler: @escaping @MainActor (Error, State) -> Void) -> ActionTask {
    switch storeTask {
    case .run(let id, let operation, _):
      return ActionTask(storeTask: .run(id: id, operation: operation, onError: handler))
    default:
      return self
    }
  }
}
