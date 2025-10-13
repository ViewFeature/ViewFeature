import XCTest

@testable import ViewFeature

/// Comprehensive unit tests for StoreTask with 100% code coverage.
///
/// Tests every enum case and associated values in StoreTask.swift
@MainActor
final class StoreTaskTests: XCTestCase {
  // MARK: - Test Fixtures

  enum TestAction {
    case increment
    case decrement
  }

  struct TestState: Equatable {
    var count = 0
  }

  // MARK: - noTask

  func test_noTask_canBeCreated() {
    // GIVEN & WHEN: Create a noTask
    let sut: StoreTask<TestAction, TestState> = .none

    // THEN: Should be noTask case
    switch sut {
    case .none:
      XCTAssertTrue(true, "noTask created successfully")
    case .run, .cancel:
      XCTFail("Expected noTask, got different case")
    }
  }

  func test_noTask_canBeCreatedMultipleTimes() {
    // GIVEN & WHEN: Create multiple noTask instances
    let task1: StoreTask<TestAction, TestState> = .none
    let task2: StoreTask<TestAction, TestState> = .none

    // THEN: Both should be noTask
    switch task1 {
    case .none:
      XCTAssertTrue(true)
    default:
      XCTFail("task1 should be noTask")
    }

    switch task2 {
    case .none:
      XCTAssertTrue(true)
    default:
      XCTFail("task2 should be noTask")
    }
  }

  // MARK: - run(id:operation:onError:)

  func test_run_withIdAndOperation() {
    // GIVEN: An ID and operation
    let taskId = "test-task"
    let operation: () async throws -> Void = {}

    // WHEN: Create a run task
    let sut: StoreTask<TestAction, TestState> = .run(
      id: taskId,
      operation: operation,
      onError: nil
    )

    // THEN: Should be run case with correct ID
    switch sut {
    case .run(let id, _, let errorHandler):
      XCTAssertEqual(id, taskId)
      XCTAssertNil(errorHandler)
    case .none, .cancel:
      XCTFail("Expected run case")
    }
  }

  func test_run_withOperationOnly() {
    // GIVEN: Only an operation (no error handler)
    let operation: () async throws -> Void = {}

    // WHEN: Create a run task with default onError
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "task",
      operation: operation
    )

    // THEN: Should have nil error handler by default
    switch sut {
    case .run(_, _, let errorHandler):
      XCTAssertNil(errorHandler, "Default onError should be nil")
    default:
      XCTFail("Expected run case")
    }
  }

  func test_run_withErrorHandler() {
    // GIVEN: Operation and error handler
    let operation: () async throws -> Void = {}
    let errorHandler: @MainActor (Error, inout TestState) -> Void = { _, _ in
      // Error handler exists
    }

    // WHEN: Create a run task with error handler
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "error-task",
      operation: operation,
      onError: errorHandler
    )

    // THEN: Should have error handler
    switch sut {
    case .run(let id, _, let handler):
      XCTAssertEqual(id, "error-task")
      XCTAssertNotNil(handler, "Error handler should be present")
    default:
      XCTFail("Expected run case")
    }
  }

  func test_run_withLongId() {
    // GIVEN: A very long task ID
    let longId = String(repeating: "a", count: 1000)
    let operation: () async throws -> Void = {}

    // WHEN: Create a run task with long ID
    let sut: StoreTask<TestAction, TestState> = .run(
      id: longId,
      operation: operation,
      onError: nil
    )

    // THEN: Should accept and store the long ID
    switch sut {
    case .run(let id, _, _):
      XCTAssertEqual(id, longId)
      XCTAssertEqual(id.count, 1000)
    default:
      XCTFail("Expected run case")
    }
  }

  func test_run_withSpecialCharactersInId() {
    // GIVEN: An ID with special characters
    let specialId = "task-🎉-日本語-123"
    let operation: () async throws -> Void = {}

    // WHEN: Create a run task
    let sut: StoreTask<TestAction, TestState> = .run(
      id: specialId,
      operation: operation,
      onError: nil
    )

    // THEN: Should accept special characters
    switch sut {
    case .run(let id, _, _):
      XCTAssertEqual(id, specialId)
    default:
      XCTFail("Expected run case")
    }
  }

  func test_run_withEmptyId() {
    // GIVEN: An empty string as ID
    let operation: () async throws -> Void = {}

    // WHEN: Create a run task with empty ID
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "",
      operation: operation,
      onError: nil
    )

    // THEN: Should accept empty string
    switch sut {
    case .run(let id, _, _):
      XCTAssertEqual(id, "")
    default:
      XCTFail("Expected run case")
    }
  }

  func test_run_operationCanThrow() async {
    // GIVEN: A throwing operation
    struct TestError: Error {}
    let operation: () async throws -> Void = {
      throw TestError()
    }

    // WHEN: Create a run task
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "throwing",
      operation: operation,
      onError: nil
    )

    // THEN: Should store the throwing operation
    switch sut {
    case .run(_, let storedOperation, _):
      // Verify operation throws
      do {
        try await storedOperation()
        XCTFail("Operation should throw")
      } catch {
        XCTAssertTrue(error is TestError)
      }
    default:
      XCTFail("Expected run case")
    }
  }

  func test_run_operationCanExecuteSuccessfully() async {
    // GIVEN: A successful operation
    var didExecute = false
    let operation: () async throws -> Void = {
      didExecute = true
    }

    // WHEN: Create and execute operation
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "success",
      operation: operation,
      onError: nil
    )

    // THEN: Operation should execute successfully
    switch sut {
    case .run(_, let storedOperation, _):
      try? await storedOperation()
      XCTAssertTrue(didExecute)
    default:
      XCTFail("Expected run case")
    }
  }

  func test_run_errorHandlerCanAccessError() {
    // GIVEN: Error handler that captures error
    var capturedError: Error?
    let testError = NSError(domain: "Test", code: 42)

    let errorHandler: @MainActor (Error, inout TestState) -> Void = { error, _ in
      capturedError = error as NSError
    }

    // WHEN: Create run task with error handler
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "test",
      operation: {},
      onError: errorHandler
    )

    // THEN: Error handler should be stored
    switch sut {
    case .run(_, _, let handler):
      XCTAssertNotNil(handler)

      // Execute handler
      var state = TestState()
      handler?(testError, &state)

      // Verify error was captured
      XCTAssertNotNil(capturedError)
      XCTAssertEqual((capturedError as? NSError)?.code, 42)
    default:
      XCTFail("Expected run case")
    }
  }

  func test_run_errorHandlerCanMutateState() {
    // GIVEN: Error handler that mutates state
    let errorHandler: @MainActor (Error, inout TestState) -> Void = { _, state in
      state.count = 999
    }

    // WHEN: Create run task and execute handler
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "mutate",
      operation: {},
      onError: errorHandler
    )

    // THEN: Handler should mutate state
    switch sut {
    case .run(_, _, let handler):
      var state = TestState(count: 0)
      let error = NSError(domain: "Test", code: 1)
      handler?(error, &state)
      XCTAssertEqual(state.count, 999)
    default:
      XCTFail("Expected run case")
    }
  }

  // MARK: - cancel(id:)

  func test_cancel_withStringId() {
    // GIVEN: A task ID
    let taskId = "task-to-cancel"

    // WHEN: Create a cancel task
    let sut: StoreTask<TestAction, TestState> = .cancel(id: taskId)

    // THEN: Should be cancel case with correct ID
    switch sut {
    case .cancel(let id):
      XCTAssertEqual(id, taskId)
    case .none, .run:
      XCTFail("Expected cancel case")
    }
  }

  func test_cancel_withEmptyId() {
    // GIVEN: An empty string ID
    let emptyId = ""

    // WHEN: Create a cancel task
    let sut: StoreTask<TestAction, TestState> = .cancel(id: emptyId)

    // THEN: Should accept empty string
    switch sut {
    case .cancel(let id):
      XCTAssertEqual(id, "")
    default:
      XCTFail("Expected cancel case")
    }
  }

  func test_cancel_withLongId() {
    // GIVEN: A very long ID
    let longId = String(repeating: "x", count: 2000)

    // WHEN: Create a cancel task
    let sut: StoreTask<TestAction, TestState> = .cancel(id: longId)

    // THEN: Should accept long ID
    switch sut {
    case .cancel(let id):
      XCTAssertEqual(id, longId)
      XCTAssertEqual(id.count, 2000)
    default:
      XCTFail("Expected cancel case")
    }
  }

  func test_cancel_withSpecialCharacters() {
    // GIVEN: ID with special characters
    let specialId = "cancel-🔥-テスト-456"

    // WHEN: Create a cancel task
    let sut: StoreTask<TestAction, TestState> = .cancel(id: specialId)

    // THEN: Should accept special characters
    switch sut {
    case .cancel(let id):
      XCTAssertEqual(id, specialId)
    default:
      XCTFail("Expected cancel case")
    }
  }

  // MARK: - Integration Tests

  func test_allCases_canBeCreatedWithSameTypes() {
    // GIVEN & WHEN: Create all three enum cases
    let noTask: StoreTask<TestAction, TestState> = .none
    let runTask: StoreTask<TestAction, TestState> = .run(
      id: "run",
      operation: {},
      onError: nil
    )
    let cancelTask: StoreTask<TestAction, TestState> = .cancel(id: "cancel")

    // THEN: All should be valid cases
    switch noTask {
    case .none: XCTAssertTrue(true)
    default: XCTFail("noTask failed")
    }

    switch runTask {
    case .run: XCTAssertTrue(true)
    default: XCTFail("runTask failed")
    }

    switch cancelTask {
    case .cancel: XCTAssertTrue(true)
    default: XCTFail("cancelTask failed")
    }
  }

  func test_run_withComplexErrorHandler() {
    // GIVEN: Complex error handler with multiple operations
    var errorLog: [(error: String, count: Int)] = []

    let complexHandler: @MainActor (Error, inout TestState) -> Void = { error, state in
      state.count += 1
      errorLog.append((error: error.localizedDescription, count: state.count))
    }

    // WHEN: Create run task and execute handler multiple times
    let sut: StoreTask<TestAction, TestState> = .run(
      id: "complex",
      operation: {},
      onError: complexHandler
    )

    // THEN: Handler should work correctly
    switch sut {
    case .run(_, _, let handler):
      var state = TestState(count: 0)

      handler?(NSError(domain: "E1", code: 1), &state)
      XCTAssertEqual(state.count, 1)

      handler?(NSError(domain: "E2", code: 2), &state)
      XCTAssertEqual(state.count, 2)

      XCTAssertEqual(errorLog.count, 2)
    default:
      XCTFail("Expected run case")
    }
  }

  func test_differentActionTypes_createDifferentTaskTypes() {
    // GIVEN: Different Action types
    enum Action1 { case a }
    enum Action2 { case b }

    // WHEN: Create tasks with different types
    let task1: StoreTask<Action1, TestState> = .none
    let task2: StoreTask<Action2, TestState> = .none

    // THEN: Both should be valid but different types
    switch task1 {
    case .none: XCTAssertTrue(true)
    default: XCTFail()
    }

    switch task2 {
    case .none: XCTAssertTrue(true)
    default: XCTFail()
    }
  }

  func test_differentStateTypes_createDifferentTaskTypes() {
    // GIVEN: Different State types
    struct State1: Equatable { var value = 0 }
    struct State2: Equatable { var text = "" }

    // WHEN: Create tasks with different state types
    let task1: StoreTask<TestAction, State1> = .none
    let task2: StoreTask<TestAction, State2> = .none

    // THEN: Both should be valid but different types
    switch task1 {
    case .none: XCTAssertTrue(true)
    default: XCTFail()
    }

    switch task2 {
    case .none: XCTAssertTrue(true)
    default: XCTFail()
    }
  }
}
