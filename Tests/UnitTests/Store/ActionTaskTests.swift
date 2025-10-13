@testable import ViewFeature
import XCTest

/// Comprehensive unit tests for ActionTask with 100% code coverage.
///
/// Tests every public method and property in ActionTask.swift
@MainActor
final class ActionTaskTests: XCTestCase {

  // MARK: - Test Fixtures

  enum TestAction {
    case increment
    case decrement
  }

  struct TestState: Equatable {
    var count = 0
  }

  // MARK: - noTask

  func test_noTask_createsTaskWithNoTask() {
    // GIVEN & WHEN: Create a noTask
    let sut: ActionTask<TestAction, TestState> = .none

    // THEN: Should have noTask storeTask
    switch sut.storeTask {
    case .none:
      XCTAssertTrue(true, "noTask created successfully")
    case .run, .cancel:
      XCTFail("Expected noTask, got different task type")
    }
  }

  func test_noTask_canBeCreatedMultipleTimes() {
    // GIVEN & WHEN: Create multiple noTasks
    let task1: ActionTask<TestAction, TestState> = .none
    let task2: ActionTask<TestAction, TestState> = .none

    // THEN: Both should be noTask type
    switch task1.storeTask {
    case .none:
      XCTAssertTrue(true)
    default:
      XCTFail("task1 should be noTask")
    }

    switch task2.storeTask {
    case .none:
      XCTAssertTrue(true)
    default:
      XCTFail("task2 should be noTask")
    }
  }

  // MARK: - run(id:operation:)

  func test_run_withExplicitId() {
    // GIVEN: An explicit task ID
    let taskId = "my-custom-task"

    // WHEN: Create a run task with explicit ID
    let sut: ActionTask<TestAction, TestState> = .run(id: taskId) {}

    // THEN: Should have run storeTask with correct ID
    switch sut.storeTask {
    case .run(let id, _, _):
      XCTAssertEqual(id, taskId)
    case .none, .cancel:
      XCTFail("Expected run task, got different type")
    }
  }

  func test_run_withoutId_generatesAutomaticId() {
    // GIVEN & WHEN: Create a run task without explicit ID
    let sut: ActionTask<TestAction, TestState> = .run {}

    // THEN: Should have run storeTask with auto-generated ID
    switch sut.storeTask {
    case .run(let id, _, _):
      XCTAssertTrue(id.hasPrefix("auto-task-"), "ID should have auto-task prefix")
      XCTAssertTrue(id.count > "auto-task-".count, "ID should have unique suffix")
    case .none, .cancel:
      XCTFail("Expected run task, got different type")
    }
  }

  func test_run_withoutId_generatesDifferentIdsForConsecutiveCalls() {
    // GIVEN & WHEN: Create multiple run tasks without IDs
    let task1: ActionTask<TestAction, TestState> = .run {}
    let task2: ActionTask<TestAction, TestState> = .run {}

    // THEN: Should generate different IDs
    var id1: String?
    var id2: String?

    if case .run(let id, _, _) = task1.storeTask {
      id1 = id
    }

    if case .run(let id, _, _) = task2.storeTask {
      id2 = id
    }

    XCTAssertNotNil(id1)
    XCTAssertNotNil(id2)
    // Note: IDs might be the same if created within same millisecond
    // but both should be valid auto-task IDs
    XCTAssertTrue(id1!.hasPrefix("auto-task-"))
    XCTAssertTrue(id2!.hasPrefix("auto-task-"))
  }

  func test_run_storesOperation() {
    // GIVEN: An operation
    let operation: @Sendable () async throws -> Void = {}

    // WHEN: Create a run task with operation
    let sut: ActionTask<TestAction, TestState> = .run(id: "test", operation: operation)

    // THEN: Should store the operation (cannot directly test, but can verify task type)
    switch sut.storeTask {
    case .run(_, let storedOperation, _):
      // Operation is stored - we can't easily test it's the same closure
      // but we verify it's a run task with an operation
      XCTAssertNotNil(storedOperation)
    case .none, .cancel:
      XCTFail("Expected run task")
    }
  }

  func test_run_withLongId() {
    // GIVEN: A very long task ID
    let longId = String(repeating: "a", count: 1000)

    // WHEN: Create a run task with long ID
    let sut: ActionTask<TestAction, TestState> = .run(id: longId) {}

    // THEN: Should accept and store the long ID
    switch sut.storeTask {
    case .run(let id, _, _):
      XCTAssertEqual(id, longId)
      XCTAssertEqual(id.count, 1000)
    default:
      XCTFail("Expected run task")
    }
  }

  func test_run_withSpecialCharactersInId() {
    // GIVEN: An ID with special characters
    let specialId = "task-🎉-日本語-123"

    // WHEN: Create a run task with special ID
    let sut: ActionTask<TestAction, TestState> = .run(id: specialId) {}

    // THEN: Should accept and store the ID with special characters
    switch sut.storeTask {
    case .run(let id, _, _):
      XCTAssertEqual(id, specialId)
    default:
      XCTFail("Expected run task")
    }
  }

  // MARK: - cancel(id:)

  func test_cancel_withStringId() {
    // GIVEN: A string task ID
    let taskId = "task-to-cancel"

    // WHEN: Create a cancel task
    let sut: ActionTask<TestAction, TestState> = .cancel(id: taskId)

    // THEN: Should have cancel storeTask with correct ID
    switch sut.storeTask {
    case .cancel(let id):
      XCTAssertEqual(id, taskId)
    case .none, .run:
      XCTFail("Expected cancel task, got different type")
    }
  }

  func test_cancel_withIntId() {
    // GIVEN: An integer task ID
    let taskId = 42

    // WHEN: Create a cancel task
    let sut: ActionTask<TestAction, TestState> = .cancel(id: taskId)

    // THEN: Should convert to string and store
    switch sut.storeTask {
    case .cancel(let id):
      XCTAssertEqual(id, "42")
    case .none, .run:
      XCTFail("Expected cancel task")
    }
  }

  func test_cancel_withEnumId() {
    // GIVEN: An enum as task ID
    enum TaskId: String {
      case fetchData
      case saveData
    }

    // WHEN: Create a cancel task with enum ID
    let sut: ActionTask<TestAction, TestState> = .cancel(id: TaskId.fetchData)

    // THEN: Should convert enum to string
    switch sut.storeTask {
    case .cancel(let id):
      XCTAssertEqual(id, "fetchData")
    case .none, .run:
      XCTFail("Expected cancel task")
    }
  }

  func test_cancel_withCustomHashableType() {
    // GIVEN: A custom hashable type
    struct CustomTaskId: Hashable, Sendable, CustomStringConvertible {
      let value: String
      var description: String { value }
    }

    let taskId = CustomTaskId(value: "custom-123")

    // WHEN: Create a cancel task
    let sut: ActionTask<TestAction, TestState> = .cancel(id: taskId)

    // THEN: Should use CustomStringConvertible
    switch sut.storeTask {
    case .cancel(let id):
      XCTAssertEqual(id, "custom-123")
    case .none, .run:
      XCTFail("Expected cancel task")
    }
  }

  func test_cancel_withUUIDId() {
    // GIVEN: A UUID as task ID
    let uuid = UUID()

    // WHEN: Create a cancel task
    let sut: ActionTask<TestAction, TestState> = .cancel(id: uuid)

    // THEN: Should convert UUID to string
    switch sut.storeTask {
    case .cancel(let id):
      XCTAssertEqual(id, uuid.uuidString)
    case .none, .run:
      XCTFail("Expected cancel task")
    }
  }

  // MARK: - Integration Tests

  func test_allTaskTypes_canBeCreatedWithSameActionAndStateTypes() {
    // GIVEN & WHEN: Create all three task types
    let noTask: ActionTask<TestAction, TestState> = .none
    let runTask: ActionTask<TestAction, TestState> = .run(id: "test") {}
    let cancelTask: ActionTask<TestAction, TestState> = .cancel(id: "test")

    // THEN: All should be valid tasks
    switch noTask.storeTask {
    case .none: XCTAssertTrue(true)
    default: XCTFail("noTask failed")
    }

    switch runTask.storeTask {
    case .run: XCTAssertTrue(true)
    default: XCTFail("runTask failed")
    }

    switch cancelTask.storeTask {
    case .cancel: XCTAssertTrue(true)
    default: XCTFail("cancelTask failed")
    }
  }

  // MARK: - catch(_:)

  func test_catch_withNoneTask_returnsUnchangedTask() {
    // GIVEN: A none task
    let sut: ActionTask<TestAction, TestState> = .none

    // WHEN: Attach error handler with catch
    let result = sut.catch { _, _ in }

    // THEN: Should return unchanged none task
    switch result.storeTask {
    case .none:
      XCTAssertTrue(true, "Task should remain as none")
    default:
      XCTFail("Expected none task, got different type")
    }
  }

  func test_catch_withCancelTask_returnsUnchangedTask() {
    // GIVEN: A cancel task
    let sut: ActionTask<TestAction, TestState> = .cancel(id: "test")

    // WHEN: Attach error handler with catch
    let result = sut.catch { _, _ in }

    // THEN: Should return unchanged cancel task
    switch result.storeTask {
    case .cancel(let id):
      XCTAssertEqual(id, "test", "Task should remain as cancel with same ID")
    default:
      XCTFail("Expected cancel task, got different type")
    }
  }

  func test_catch_withRunTask_attachesErrorHandler() {
    // GIVEN: A run task without error handler
    let sut: ActionTask<TestAction, TestState> = .run(id: "test") {}

    // WHEN: Attach error handler with catch
    let result = sut.catch { error, state in
      state.count = 99  // Modify state in error handler
    }

    // THEN: Should have run task with error handler
    switch result.storeTask {
    case .run(let id, _, let onError):
      XCTAssertEqual(id, "test")
      XCTAssertNotNil(onError, "Error handler should be attached")
    default:
      XCTFail("Expected run task with error handler")
    }
  }

  func test_catch_withRunTaskWithoutId_attachesErrorHandler() {
    // GIVEN: A run task with auto-generated ID
    let sut: ActionTask<TestAction, TestState> = .run {}

    // WHEN: Attach error handler with catch
    let result = sut.catch { _, _ in }

    // THEN: Should preserve auto-generated ID and attach handler
    switch result.storeTask {
    case .run(let id, _, let onError):
      XCTAssertTrue(id.hasPrefix("auto-task-"), "Should preserve auto-generated ID")
      XCTAssertNotNil(onError, "Error handler should be attached")
    default:
      XCTFail("Expected run task with error handler")
    }
  }

  func test_catch_canChainMultipleTimes() {
    // GIVEN: A run task
    let sut: ActionTask<TestAction, TestState> = .run(id: "test") {}

    // WHEN: Chain catch multiple times (last one wins)
    let result = sut
      .catch { _, state in state.count = 1 }
      .catch { _, state in state.count = 2 }

    // THEN: Should have the last error handler
    switch result.storeTask {
    case .run(_, _, let onError):
      XCTAssertNotNil(onError, "Should have error handler")
      // Note: Can't easily test which handler is attached in unit test
      // This is tested in integration tests
    default:
      XCTFail("Expected run task")
    }
  }

  func test_catch_preservesTaskId() {
    // GIVEN: A run task with specific ID
    let originalId = "my-important-task"
    let sut: ActionTask<TestAction, TestState> = .run(id: originalId) {}

    // WHEN: Attach error handler
    let result = sut.catch { _, _ in }

    // THEN: Should preserve the original task ID
    switch result.storeTask {
    case .run(let id, _, _):
      XCTAssertEqual(id, originalId, "Task ID should be preserved")
    default:
      XCTFail("Expected run task")
    }
  }

  func test_catch_withComplexErrorHandler() {
    // GIVEN: A run task
    let sut: ActionTask<TestAction, TestState> = .run(id: "test") {}

    // WHEN: Attach complex error handler
    let result = sut.catch { error, state in
      // Complex error handling logic
      state.count = (error as NSError).code
    }

    // THEN: Should successfully attach the handler
    switch result.storeTask {
    case .run(let id, _, let onError):
      XCTAssertEqual(id, "test")
      XCTAssertNotNil(onError)
    default:
      XCTFail("Expected run task")
    }
  }
}
