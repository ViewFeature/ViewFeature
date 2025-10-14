import Foundation

/// Task identifiers (String, Int, UUID, or custom enums).
public typealias TaskID = Hashable & Sendable

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
    let stringId = String(describing: id)
    return ActionTask(storeTask: .run(id: stringId, operation: operation, onError: nil))
  }

  /// Cancels a running task by its ID. Does nothing if the task isn't running.
  public static func cancel<ID: TaskID>(id: ID) -> ActionTask {
    let stringId = String(describing: id)
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
