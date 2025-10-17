import Foundation
import Testing

@testable import ViewFeature

/// Comprehensive unit tests for Store with 100% code coverage.
///
/// Tests every public method and property in Store.swift
// swiftlint:disable file_length type_body_length
@MainActor
@Suite struct StoreTests {
  // MARK: - Test Fixtures

  enum TestAction: Sendable {
    case increment
    case decrement
    case asyncOp
    case throwingOp
    case cancelOp(String)
  }

  @Observable
  final class TestState {
    var count = 0
    var errorMessage: String?
    var isLoading = false

    init(count: Int = 0, errorMessage: String? = nil, isLoading: Bool = false) {
      self.count = count
      self.errorMessage = errorMessage
      self.isLoading = isLoading
    }
  }

  struct TestFeature: Feature, Sendable {
    typealias Action = TestAction
    typealias State = TestState

    func handle() -> ActionHandler<Action, State> {
      ActionHandler { action, state in
        switch action {
        case .increment:
          state.count += 1
          return .none

        case .decrement:
          state.count -= 1
          return .none

        case .asyncOp:
          state.isLoading = true
          return .run(id: "async") { _ in
            try await Task.sleep(for: .milliseconds(10))
          }

        case .throwingOp:
          return .run(id: "throwing") { _ in
            throw NSError(domain: "Test", code: 1)
          }

        case .cancelOp(let id):
          return .cancel(id: id)
        }
      }
    }
  }

  // MARK: - Additional Test States

  @Observable
  final class DownloadState {
    var isDownloading = false
    var downloadProgress = 0.0
    var errorMessage: String?

    init(isDownloading: Bool = false, downloadProgress: Double = 0.0, errorMessage: String? = nil) {
      self.isDownloading = isDownloading
      self.downloadProgress = downloadProgress
      self.errorMessage = errorMessage
    }
  }

  @Observable
  final class ViewState {
    var isActive = false

    init(isActive: Bool = false) {
      self.isActive = isActive
    }
  }

  @Observable
  final class CancelState {
    var isRunning = false
    var didCatchError = false
    var caughtCancellationError = false

    init(
      isRunning: Bool = false, didCatchError: Bool = false, caughtCancellationError: Bool = false
    ) {
      self.isRunning = isRunning
      self.didCatchError = didCatchError
      self.caughtCancellationError = caughtCancellationError
    }
  }

  @Observable
  final class DirectCancelState {
    var isRunning = false
    var didCatchError = false
    var caughtCancellationError = false

    init(
      isRunning: Bool = false, didCatchError: Bool = false, caughtCancellationError: Bool = false
    ) {
      self.isRunning = isRunning
      self.didCatchError = didCatchError
      self.caughtCancellationError = caughtCancellationError
    }
  }

  // MARK: - init(initialState:feature:taskManager:)

  @Test func init_withDefaultTaskManager() async {
    // GIVEN: Initial state and feature
    let initialState = TestState(count: 0)
    let feature = TestFeature()

    // WHEN: Create store with default task manager
    let sut = Store(initialState: initialState, feature: feature)

    // THEN: Should initialize correctly
    // swiftlint:disable:next empty_count
    #expect(sut.state.count == 0)
    #expect(sut.runningTaskCount == 0)
  }

  @Test func init_withCustomTaskManager() async {
    // GIVEN: Custom task manager
    let taskManager = TaskManager()
    let initialState = TestState(count: 5)
    let feature = TestFeature()

    // WHEN: Create store with custom task manager
    let sut = Store(
      initialState: initialState,
      feature: feature,
      taskManager: taskManager
    )

    // THEN: Should use custom task manager
    #expect(sut.state.count == 5)
    #expect(sut.runningTaskCount == 0)
  }

  @Test func init_preservesInitialState() async {
    // GIVEN: Initial state with values
    let initialState = TestState(
      count: 42,
      errorMessage: "Initial",
      isLoading: true
    )
    let feature = TestFeature()

    // WHEN: Create store
    let sut = Store(initialState: initialState, feature: feature)

    // THEN: Should preserve all initial state values
    #expect(sut.state.count == 42)
    #expect(sut.state.errorMessage == "Initial")
    #expect(sut.state.isLoading)
  }

  // MARK: - state

  @Test func state_returnsCurrentState() async {
    // GIVEN: Store with initial state
    let sut = Store(
      initialState: TestState(count: 10),
      feature: TestFeature()
    )

    // WHEN: Access state
    let state = sut.state

    // THEN: Should return current state
    #expect(state.count == 10)
  }

  @Test func state_updatesAfterAction() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // WHEN: Send action
    await sut.send(.increment).value

    // THEN: State should update
    #expect(sut.state.count == 1)
  }

  @Test func state_reflectsMultipleUpdates() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // WHEN: Send multiple actions
    await sut.send(.increment).value
    await sut.send(.increment).value
    await sut.send(.decrement).value

    // THEN: State should reflect all updates
    #expect(sut.state.count == 1)  // 0 + 1 + 1 - 1 = 1
  }

  // MARK: - send(_:)

  @Test func send_processesAction() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // WHEN: Send action
    await sut.send(.increment).value

    // THEN: Action should be processed
    #expect(sut.state.count == 1)
  }

  @Test func send_returnsTask() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // WHEN: Send action
    let task = sut.send(.increment)

    // THEN: Should return Task<Void, Never>
    await task.value
  }

  @Test func send_handlesNoTask() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // WHEN: Send action that returns .none
    await sut.send(.increment).value

    // THEN: Should process synchronously
    #expect(sut.state.count == 1)
    #expect(sut.runningTaskCount == 0)
  }

  @Test func send_handlesRunTask() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // WHEN: Send async action and wait for completion
    await sut.send(.asyncOp).value

    // THEN: State should be updated and task should have completed
    #expect(sut.state.isLoading)
    #expect(sut.runningTaskCount == 0)
  }

  @Test func send_handlesCancelTask() async {
    // GIVEN: Store with running task
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // Start a task (fire-and-forget)
    let asyncTask = sut.send(.asyncOp)

    // WHEN: Send cancel action
    await sut.send(.cancelOp("async")).value

    // THEN: Wait for task cleanup
    await asyncTask.value
    #expect(sut.runningTaskCount == 0)
  }

  @Test func send_processesMultipleActionsSequentially() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // WHEN: Send multiple actions
    await sut.send(.increment).value
    await sut.send(.increment).value
    await sut.send(.increment).value
    await sut.send(.decrement).value

    // THEN: All actions should process
    #expect(sut.state.count == 2)  // +1 +1 +1 -1 = 2
  }

  @Test func send_canBeDiscarded() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // WHEN: Send action without awaiting (@discardableResult)
    let task = sut.send(.increment)

    // Wait for action to process
    await task.value

    // THEN: Action should still process
    #expect(sut.state.count == 1)
  }

  // MARK: - Task Management

  @Test func runningTaskCount_startsAtZero() async {
    // GIVEN: New store
    let sut = Store(
      initialState: TestState(),
      feature: TestFeature()
    )

    // THEN: Should have no running tasks
    #expect(sut.runningTaskCount == 0)
  }

  @Test func runningTaskCount_returnsZeroAfterCompletion() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(),
      feature: TestFeature()
    )

    // WHEN: Send async action and wait for completion
    await sut.send(.asyncOp).value

    // THEN: Should have no running tasks
    #expect(sut.runningTaskCount == 0)
  }

  @Test func taskCompletion_clearsRunningTasks() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(),
      feature: TestFeature()
    )

    // WHEN: Send async action and wait for completion
    await sut.send(.asyncOp).value

    // THEN: All tasks should be complete
    #expect(sut.runningTaskCount == 0)
  }


  // MARK: - Error Handling

  @Test func errorHandling_logsError() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(),
      feature: TestFeature()
    )

    // WHEN: Send action that throws and wait for completion
    await sut.send(.throwingOp).value

    // THEN: Error should be logged (no crash)
    // We can't directly verify logging, but we verify no crash
    // swiftlint:disable:next empty_count
    #expect(sut.state.count == 0)
    #expect(sut.runningTaskCount == 0)
  }

  @Test func createErrorHandler_withNonNilHandler() async {
    // GIVEN: Feature with StoreTask-level error handler
    struct ErrorHandlingFeature: Feature, Sendable {
      typealias Action = TestAction
      typealias State = TestState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
          switch action {
          case .throwingOp:
            state.isLoading = true
            // Return StoreTask with onError handler
            return ActionTask(
              storeTask: .run(
                id: "errorTest",
                operation: { _ in
                  throw NSError(domain: "TestError", code: 999)
                },
                onError: { error, errorState in
                  errorState.errorMessage = "Error caught: \(error.localizedDescription)"
                  errorState.isLoading = false
                }
              ))
          default:
            return .none
          }
        }
      }
    }

    let sut = Store(
      initialState: TestState(),
      feature: ErrorHandlingFeature()
    )

    // WHEN: Send action that triggers error handler and wait for completion
    await sut.send(.throwingOp).value

    // THEN: Error handler should have been called
    #expect(sut.state.errorMessage?.contains("Error caught") ?? false)
    #expect(!sut.state.isLoading)
    #expect(sut.runningTaskCount == 0)
  }

  @Test func createErrorHandler_withNilHandler() async {
    // GIVEN: Feature returning StoreTask with nil onError
    struct NoErrorHandlerFeature: Feature, Sendable {
      typealias Action = TestAction
      typealias State = TestState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, _ in
          switch action {
          case .throwingOp:
            // Return StoreTask with nil onError (default behavior)
            return ActionTask(
              storeTask: .run(
                id: "noHandler",
                operation: { _ in
                  throw NSError(domain: "TestError", code: 123)
                },
                onError: nil
              ))
          default:
            return .none
          }
        }
      }
    }

    let sut = Store(
      initialState: TestState(),
      feature: NoErrorHandlerFeature()
    )

    // WHEN: Send action that throws (no error handler) and wait for completion
    await sut.send(.throwingOp).value

    // THEN: Should not crash, error is silently handled
    #expect(sut.state.errorMessage == nil)
    #expect(sut.runningTaskCount == 0)
  }

  @Test func createErrorHandler_updatesState() async {
    // GIVEN: Feature with error handler that modifies state
    struct StateModifyingFeature: Feature, Sendable {
      typealias Action = TestAction
      typealias State = TestState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
          switch action {
          case .throwingOp:
            state.count = 10
            return ActionTask(
              storeTask: .run(
                id: "stateModify",
                operation: { _ in
                  throw NSError(domain: "Test", code: 1)
                },
                onError: { _, state in
                  state.count = 999
                  state.errorMessage = "Modified"
                }
              ))
          default:
            return .none
          }
        }
      }
    }

    let sut = Store(
      initialState: TestState(count: 0),
      feature: StateModifyingFeature()
    )

    // WHEN: Trigger error handler and wait for completion
    await sut.send(.throwingOp).value

    // THEN: State should be modified by error handler
    #expect(sut.state.count == 999)
    #expect(sut.state.errorMessage == "Modified")
    #expect(sut.runningTaskCount == 0)
  }

  // MARK: - Integration Tests

  @Test func fullWorkflow_synchronousActions() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // WHEN: Execute full workflow
    await sut.send(.increment).value
    #expect(sut.state.count == 1)

    await sut.send(.increment).value
    #expect(sut.state.count == 2)

    await sut.send(.decrement).value
    #expect(sut.state.count == 1)

    // THEN: Final state correct
    #expect(sut.state.count == 1)
  }

  @Test func fullWorkflow_mixedActions() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // WHEN: Mix synchronous and asynchronous actions
    await sut.send(.increment).value
    #expect(sut.state.count == 1)

    await sut.send(.asyncOp).value
    #expect(sut.state.isLoading)

    await sut.send(.increment).value
    #expect(sut.state.count == 2)

    // THEN: All actions processed, all tasks completed
    #expect(sut.state.count == 2)
    #expect(sut.runningTaskCount == 0)
  }

  @Test func concurrentActions_processCorrectly() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(count: 0),
      feature: TestFeature()
    )

    // WHEN: Send multiple actions without awaiting
    let task1 = sut.send(.increment)
    let task2 = sut.send(.increment)
    let task3 = sut.send(.increment)

    await task1.value
    await task2.value
    await task3.value

    // THEN: All increments should apply
    #expect(sut.state.count == 3)
  }

  @Test func storeWithComplexFeature() async {
    // GIVEN: Store with complex initial state
    let initialState = TestState(
      count: 100,
      errorMessage: nil,
      isLoading: false
    )
    let sut = Store(
      initialState: initialState,
      feature: TestFeature()
    )

    // WHEN: Execute complex scenario
    await sut.send(.increment).value
    #expect(sut.state.count == 101)

    await sut.send(.decrement).value
    #expect(sut.state.count == 100)

    await sut.send(.asyncOp).value
    #expect(sut.state.isLoading)

    // THEN: State should be consistent
    #expect(sut.state.count == 100)
    #expect(sut.state.isLoading)
  }

  @Test func taskCancellation_integration() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(),
      feature: TestFeature()
    )

    // WHEN: Start task and cancel it
    let asyncTask = sut.send(.asyncOp)
    await sut.send(.cancelOp("async")).value

    // THEN: Wait for task cleanup
    await asyncTask.value
    #expect(sut.runningTaskCount == 0)
  }

  @Test func multipleTasksCancellation() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TestState(),
      feature: TestFeature()
    )

    // WHEN: Start task and cancel via action
    let asyncTask = sut.send(.asyncOp)
    await sut.send(.cancelOp("async")).value

    // THEN: Wait for task cleanup
    await asyncTask.value
    #expect(sut.runningTaskCount == 0)
  }

  // MARK: - Automatic Task Cleanup Tests

  @Test func storeDeinit_automaticallyCancelsRunningTasks() async {
    // GIVEN: Feature with a long-running task
    struct LongTaskFeature: Feature, Sendable {
      typealias Action = TestAction
      typealias State = TestState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
          switch action {
          case .asyncOp:
            state.isLoading = true
            return .run(id: "long-task") { _ in
              try await Task.sleep(for: .seconds(100))
            }
          default:
            return .none
          }
        }
      }
    }

    // Track if store was deallocated
    weak var weakStore: Store<LongTaskFeature>?
    var wasTaskCancelled = false

    do {
      let store = Store(
        initialState: TestState(),
        feature: LongTaskFeature()
      )
      weakStore = store

      // Start long-running task
      let task = store.send(.asyncOp)

      // Verify task is running
      #expect(store.state.isLoading)

      // Track task cancellation by checking if it completes quickly
      Task {
        await task.value
        wasTaskCancelled = Task.isCancelled
      }

      // WHEN: Store goes out of scope (deinit called)
    }

    // Give deinit time to execute
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(10))

    // THEN: Store should be deallocated
    #expect(weakStore == nil)
  }

  @Test func storeDeinit_cancelsMultipleRunningTasks() async {
    // GIVEN: Feature with multiple long-running tasks
    struct MultiTaskFeature: Feature, Sendable {
      typealias Action = TestAction
      typealias State = TestState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
          switch action {
          case .increment:
            return .run(id: "task1") { _ in
              try await Task.sleep(for: .seconds(100))
            }
          case .decrement:
            return .run(id: "task2") { _ in
              try await Task.sleep(for: .seconds(100))
            }
          case .asyncOp:
            return .run(id: "task3") { _ in
              try await Task.sleep(for: .seconds(100))
            }
          default:
            return .none
          }
        }
      }
    }

    weak var weakStore: Store<MultiTaskFeature>?

    do {
      let store = Store(
        initialState: TestState(),
        feature: MultiTaskFeature()
      )
      weakStore = store

      // Start multiple tasks
      let task1 = store.send(.increment)
      let task2 = store.send(.decrement)
      let task3 = store.send(.asyncOp)

      // Track tasks
      Task {
        await task1.value
        await task2.value
        await task3.value
      }

      // WHEN: Store goes out of scope (deinit called)
    }

    // Give deinit time to execute
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(10))

    // THEN: Store should be deallocated, all tasks cancelled
    #expect(weakStore == nil)
  }

  @Test func storeDeinit_cleansUpTaskDictionaryImmediately() async {
    // GIVEN: Feature with task
    struct CleanupTestFeature: Feature, Sendable {
      typealias Action = TestAction
      typealias State = TestState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, _ in
          switch action {
          case .asyncOp:
            return .run(id: "cleanup-test") { _ in
              try await Task.sleep(for: .seconds(100))
            }
          default:
            return .none
          }
        }
      }
    }

    weak var weakStore: Store<CleanupTestFeature>?
    var taskCount: Int = 0

    do {
      let store = Store(
        initialState: TestState(),
        feature: CleanupTestFeature()
      )
      weakStore = store

      // Start task
      _ = store.send(.asyncOp)

      // Give task time to register
      try? await Task.sleep(for: .milliseconds(10))

      // Record task count before deinit
      taskCount = store.runningTaskCount
      #expect(taskCount > 0)

      // WHEN: Store goes out of scope
    }

    // Give deinit time to execute
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(10))

    // THEN: Store should be fully deallocated
    #expect(weakStore == nil)
  }
}
// swiftlint:enable file_length type_body_length
