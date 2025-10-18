import Foundation
import Testing

@testable import ViewFeature

/// Comprehensive unit tests for StoreTask with 100% code coverage.
///
/// Tests every enum case and associated values in StoreTask.swift
@MainActor
@Suite struct StoreTaskTests {
  // MARK: - Test Fixtures

  enum TestAction {
    case increment
    case decrement
  }

  @Observable
  final class TestState: @unchecked Sendable {
    var count = 0

    init(count: Int = 0) {
      self.count = count
    }
  }

  // MARK: - noTask

  @Test func noTask_canBeCreated() {
    // GIVEN & WHEN: Create a noTask
    let sut: StoreTask<TestAction, TestState> = .none

    // THEN: Should be noTask case
    switch sut {
    case .none:
      #expect(true, "noTask created successfully")
    case .run, .cancels:
      Issue.record("Expected noTask, got different case")
    }
  }

  @Test func noTask_canBeCreatedMultipleTimes() {
    // GIVEN & WHEN: Create multiple noTask instances
    let task1: StoreTask<TestAction, TestState> = .none
    let task2: StoreTask<TestAction, TestState> = .none

    // THEN: Both should be noTask
    switch task1 {
    case .none:
      #expect(Bool(true))
    default:
      Issue.record("task1 should be noTask")
    }

    switch task2 {
    case .none:
      #expect(Bool(true))
    default:
      Issue.record("task2 should be noTask")
    }
  }

  // MARK: - run(id:operation:onError:)

  @Test func run_withIdAndOperation() {
    // GIVEN: An ID and operation
    let taskId = "test-task"
    let operation: @Sendable (TestState) async throws -> Void = { _ in }

    // WHEN: Create a run task
    let sut: StoreTask<TestAction, TestState> = .run(
      id: taskId,
      operation: operation,
      onError: nil,
      cancelInFlight: false
    )

    // THEN: Should be run case with correct ID
    switch sut {
    case .run(let id, _, let errorHandler, _):
      #expect(id == taskId)
      #expect(errorHandler == nil)
    case .none, .cancels:
      Issue.record("Expected run case")
    }
  }

  @Test func run_withOperationOnly() {
    // GIVEN: Only an operation (no error handler)
    let operation: @Sendable (TestState) async throws -> Void = { _ in }

    // WHEN: Create a run task with default onError
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "task",
      operation: operation,
      onError: nil,
      cancelInFlight: false
    )

    // THEN: Should have nil error handler by default
    switch sut {
    case .run(_, _, let errorHandler, _):
      #expect(errorHandler == nil, "Default onError should be nil")
    default:
      Issue.record("Expected run case")
    }
  }

  @Test func run_withErrorHandler() {
    // GIVEN: Operation and error handler
    let operation: @Sendable (TestState) async throws -> Void = { _ in }
    let errorHandler: @MainActor (Error, TestState) -> Void = { _, _ in
      // Error handler exists
    }

    // WHEN: Create a run task with error handler
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "error-task",
      operation: operation,
      onError: errorHandler,
      cancelInFlight: false
    )

    // THEN: Should have error handler
    switch sut {
    case .run(let id, _, let handler, _):
      #expect(id == "error-task")
      #expect(handler != nil, "Error handler should be present")
    default:
      Issue.record("Expected run case")
    }
  }

  @Test func run_withLongId() {
    // GIVEN: A very long task ID
    let longId = String(repeating: "a", count: 1000)
    let operation: @Sendable (TestState) async throws -> Void = { _ in }

    // WHEN: Create a run task with long ID
    let sut: StoreTask<TestAction, TestState> = .run(
      id: longId,
      operation: operation,
      onError: nil,
      cancelInFlight: false
    )

    // THEN: Should accept and store the long ID
    switch sut {
    case .run(let id, _, _, _):
      #expect(id == longId)
      #expect(id.count == 1000)
    default:
      Issue.record("Expected run case")
    }
  }

  @Test func run_withSpecialCharactersInId() {
    // GIVEN: An ID with special characters
    let specialId = "task-🎉-日本語-123"
    let operation: @Sendable (TestState) async throws -> Void = { _ in }

    // WHEN: Create a run task
    let sut: StoreTask<TestAction, TestState> = .run(
      id: specialId,
      operation: operation,
      onError: nil,
      cancelInFlight: false
    )

    // THEN: Should accept special characters
    switch sut {
    case .run(let id, _, _, _):
      #expect(id == specialId)
    default:
      Issue.record("Expected run case")
    }
  }

  @Test func run_withEmptyId() {
    // GIVEN: An empty string as ID
    let operation: @Sendable (TestState) async throws -> Void = { _ in }

    // WHEN: Create a run task with empty ID
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "",
      operation: operation,
      onError: nil,
      cancelInFlight: false
    )

    // THEN: Should accept empty string
    switch sut {
    case .run(let id, _, _, _):
      #expect(id == "")
    default:
      Issue.record("Expected run case")
    }
  }

  @Test func run_operationCanThrow() async {
    // GIVEN: A throwing operation
    struct TestError: Error {}
    let operation: @Sendable (TestState) async throws -> Void = { _ in
      throw TestError()
    }

    // WHEN: Create a run task
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "throwing",
      operation: operation,
      onError: nil,
      cancelInFlight: false
    )

    // THEN: Should store the throwing operation
    switch sut {
    case .run(_, let storedOperation, _, _):
      // Verify operation throws
      do {
        try await storedOperation(TestState())
        Issue.record("Operation should throw")
      } catch {
        #expect(error is TestError)
      }
    default:
      Issue.record("Expected run case")
    }
  }

  @Test func run_operationCanExecuteSuccessfully() async {
    // GIVEN: A successful operation using an actor to track execution
    actor ExecutionTracker {
      var didExecute = false

      func markExecuted() {
        didExecute = true
      }

      func wasExecuted() -> Bool {
        didExecute
      }
    }

    let tracker = ExecutionTracker()
    let operation: @Sendable (TestState) async throws -> Void = { _ in
      await tracker.markExecuted()
    }

    // WHEN: Create and execute operation
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "success",
      operation: operation,
      onError: nil,
      cancelInFlight: false
    )

    // THEN: Operation should execute successfully
    switch sut {
    case .run(_, let storedOperation, _, _):
      try? await storedOperation(TestState())
      let executed = await tracker.wasExecuted()
      #expect(executed)
    default:
      Issue.record("Expected run case")
    }
  }

  @Test func run_errorHandlerCanAccessError() {
    // GIVEN: Error handler that captures error
    var capturedError: Error?
    let testError = NSError(domain: "Test", code: 42)

    let errorHandler: @MainActor (Error, TestState) -> Void = { error, _ in
      capturedError = error as NSError
    }

    // WHEN: Create run task with error handler
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "test",
      operation: { _ in },
      onError: errorHandler,
      cancelInFlight: false
    )

    // THEN: Error handler should be stored
    switch sut {
    case .run(_, _, let handler, _):
      #expect(handler != nil)

      // Execute handler
      var state = TestState()
      handler?(testError, state)

      // Verify error was captured
      #expect(capturedError != nil)
      #expect((capturedError as? NSError)?.code == 42)
    default:
      Issue.record("Expected run case")
    }
  }

  @Test func run_errorHandlerCanMutateState() {
    // GIVEN: Error handler that mutates state
    let errorHandler: @MainActor (Error, TestState) -> Void = { _, state in
      state.count = 999
    }

    // WHEN: Create run task and execute handler
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "mutate",
      operation: { _ in },
      onError: errorHandler,
      cancelInFlight: false
    )

    // THEN: Handler should mutate state
    switch sut {
    case .run(_, _, let handler, _):
      var state = TestState(count: 0)
      let error = NSError(domain: "Test", code: 1)
      handler?(error, state)
      #expect(state.count == 999)
    default:
      Issue.record("Expected run case")
    }
  }

  // MARK: - cancels(ids:)

  @Test func cancels_withStringIds() {
    // GIVEN: Task IDs
    let taskIds = ["task-to-cancel"]

    // WHEN: Create a cancels task
    let sut: StoreTask<TestAction, TestState> = .cancels(ids: taskIds)

    // THEN: Should be cancels case with correct IDs
    switch sut {
    case .cancels(let ids):
      #expect(ids == taskIds)
    case .none, .run:
      Issue.record("Expected cancels case")
    }
  }

  @Test func cancels_withEmptyId() {
    // GIVEN: An empty string ID
    let emptyIds = [""]

    // WHEN: Create a cancels task
    let sut: StoreTask<TestAction, TestState> = .cancels(ids: emptyIds)

    // THEN: Should accept empty string
    switch sut {
    case .cancels(let ids):
      #expect(ids == [""])
    default:
      Issue.record("Expected cancels case")
    }
  }

  @Test func cancels_withLongId() {
    // GIVEN: A very long ID
    let longId = String(repeating: "x", count: 2000)
    let longIds = [longId]

    // WHEN: Create a cancels task
    let sut: StoreTask<TestAction, TestState> = .cancels(ids: longIds)

    // THEN: Should accept long ID
    switch sut {
    case .cancels(let ids):
      #expect(ids == [longId])
      #expect(ids.first?.count == 2000)
    default:
      Issue.record("Expected cancels case")
    }
  }

  @Test func cancels_withSpecialCharacters() {
    // GIVEN: ID with special characters
    let specialId = "cancel-🔥-テスト-456"
    let specialIds = [specialId]

    // WHEN: Create a cancels task
    let sut: StoreTask<TestAction, TestState> = .cancels(ids: specialIds)

    // THEN: Should accept special characters
    switch sut {
    case .cancels(let ids):
      #expect(ids == [specialId])
    default:
      Issue.record("Expected cancels case")
    }
  }

  @Test func cancels_withMultipleIds() {
    // GIVEN: Multiple task IDs
    let taskIds = ["task-1", "task-2", "task-3"]

    // WHEN: Create a cancels task with multiple IDs
    let sut: StoreTask<TestAction, TestState> = .cancels(ids: taskIds)

    // THEN: Should store all IDs
    switch sut {
    case .cancels(let ids):
      #expect(ids == taskIds)
      #expect(ids.count == 3)
    default:
      Issue.record("Expected cancels case")
    }
  }

  @Test func cancels_withEmptyArray() {
    // GIVEN: Empty array
    let emptyIds: [String] = []

    // WHEN: Create a cancels task with empty array
    let sut: StoreTask<TestAction, TestState> = .cancels(ids: emptyIds)

    // THEN: Should accept empty array
    switch sut {
    case .cancels(let ids):
      #expect(ids.isEmpty)
    default:
      Issue.record("Expected cancels case")
    }
  }

  // MARK: - Integration Tests

  @Test func allCases_canBeCreatedWithSameTypes() {
    // GIVEN & WHEN: Create all three enum cases
    let noTask: StoreTask<TestAction, TestState> = .none
    let runTask: StoreTask<TestAction, TestState> = .run(
      id: "run",
      operation: { _ in },
      onError: nil,
      cancelInFlight: false
    )
    let cancelsTask: StoreTask<TestAction, TestState> = .cancels(ids: ["cancel"])

    // THEN: All should be valid cases
    switch noTask {
    case .none: #expect(Bool(true))
    default: Issue.record("noTask failed")
    }

    switch runTask {
    case .run: #expect(Bool(true))
    default: Issue.record("runTask failed")
    }

    switch cancelsTask {
    case .cancels: #expect(Bool(true))
    default: Issue.record("cancelsTask failed")
    }
  }

  @Test func run_withComplexErrorHandler() {
    // GIVEN: Complex error handler with multiple operations
    var errorLog: [(error: String, count: Int)] = []

    let complexHandler: @MainActor (Error, TestState) -> Void = { error, state in
      state.count += 1
      errorLog.append((error: error.localizedDescription, count: state.count))
    }

    // WHEN: Create run task and execute handler multiple times
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "complex",
      operation: { _ in },
      onError: complexHandler,
      cancelInFlight: false
    )

    // THEN: Handler should work correctly
    switch sut {
    case .run(_, _, let handler, _):
      var state = TestState(count: 0)

      handler?(NSError(domain: "E1", code: 1), state)
      #expect(state.count == 1)

      handler?(NSError(domain: "E2", code: 2), state)
      #expect(state.count == 2)

      #expect(errorLog.count == 2)
    default:
      Issue.record("Expected run case")
    }
  }

  @Test func differentActionTypes_createDifferentTaskTypes() {
    // GIVEN: Different Action types
    enum Action1 { case actionA }
    enum Action2 { case actionB }

    // WHEN: Create tasks with different types
    let task1: StoreTask<Action1, TestState> = .none
    let task2: StoreTask<Action2, TestState> = .none

    // THEN: Both should be valid but different types
    switch task1 {
    case .none: #expect(Bool(true))
    default: Issue.record()
    }

    switch task2 {
    case .none: #expect(Bool(true))
    default: Issue.record()
    }
  }

  @Test func differentStateTypes_createDifferentTaskTypes() {
    // GIVEN: Different State types
    struct State1: Equatable { var value = 0 }
    struct State2: Equatable { var text = "" }

    // WHEN: Create tasks with different state types
    let task1: StoreTask<TestAction, State1> = .none
    let task2: StoreTask<TestAction, State2> = .none

    // THEN: Both should be valid but different types
    switch task1 {
    case .none: #expect(Bool(true))
    default: Issue.record()
    }

    switch task2 {
    case .none: #expect(Bool(true))
    default: Issue.record()
    }
  }
}
