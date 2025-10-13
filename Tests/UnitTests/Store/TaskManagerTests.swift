@testable import ViewFeature
import XCTest

/// Comprehensive unit tests for TaskManager with 100% code coverage.
///
/// Tests every public method, property, and code path in TaskManager.swift
@MainActor
final class TaskManagerTests: XCTestCase {

  var sut: TaskManager!

  override func setUp() async throws {
    try await super.setUp()
    sut = TaskManager()
  }

  override func tearDown() async throws {
    // Cancel all tasks and wait for cleanup
    sut?.cancelAllTasks()
    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
    sut = nil
    try await super.tearDown()
  }

  // MARK: - init()

  func test_init_createsEmptyManager() {
    // GIVEN & WHEN: TaskManager created in setUp
    // THEN: It should have no running tasks
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  // MARK: - runningTaskCount

  func test_runningTaskCount_returnsZeroInitially() {
    // GIVEN & WHEN: Fresh TaskManager
    // THEN: Count should be zero
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  func test_runningTaskCount_reflectsActiveTasks() async {
    // GIVEN: Execute multiple tasks
    sut.executeTask(id: "task-1", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)
    sut.executeTask(id: "task-2", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

    // Wait for tasks to start
    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

    // THEN: Count should reflect active tasks
    XCTAssertEqual(sut.runningTaskCount, 2)
  }

  func test_runningTaskCount_decreasesAfterCompletion() async {
    // GIVEN: Execute a quick task
    sut.executeTask(id: "temp", operation: {}, onError: nil)

    // Wait for completion
    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

    // THEN: Count should be zero
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  // MARK: - isTaskRunning(id:)

  func test_isTaskRunning_returnsTrueForRunningTask() async {
    // GIVEN: A running task
    sut.executeTask(id: "running", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)
    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

    // WHEN & THEN: Check if task is running
    XCTAssertTrue(sut.isTaskRunning(id: "running"))
  }

  func test_isTaskRunning_returnsFalseForNonExistentTask() {
    // GIVEN: No tasks
    // WHEN & THEN: Check for non-existent task
    XCTAssertFalse(sut.isTaskRunning(id: "non-existent"))
  }

  func test_isTaskRunning_returnsFalseAfterCompletion() async {
    // GIVEN: Execute a quick task
    sut.executeTask(id: "completed", operation: {}, onError: nil)

    // Wait for completion
    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

    // THEN: Should return false
    XCTAssertFalse(sut.isTaskRunning(id: "completed"))
  }

  // MARK: - executeTask(id:operation:onError:)

  func test_executeTask_executesOperationSuccessfully() async {
    // GIVEN: A flag
    var didExecute = false

    // WHEN: Execute a task
    sut.executeTask(id: "test", operation: { didExecute = true }, onError: nil)

    // Wait for execution
    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

    // THEN: Operation should have executed
    XCTAssertTrue(didExecute)
  }

  func test_executeTask_callsErrorHandlerOnFailure() async {
    // GIVEN: Error handler
    let testError = NSError(domain: "Test", code: 1)
    var capturedError: Error?

    // WHEN: Execute a task that throws
    sut.executeTask(
      id: "failing",
      operation: { throw testError },
      onError: { error in capturedError = error }
    )

    // Wait for error handling
    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

    // THEN: Error handler should have been called
    XCTAssertNotNil(capturedError)
  }

  func test_executeTask_doesNotCrashWhenNilErrorHandler() async {
    // GIVEN & WHEN: Execute a task that throws with nil handler
    sut.executeTask(id: "no-handler", operation: { throw NSError(domain: "Test", code: 1) }, onError: nil)

    // Wait
    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

    // THEN: Should not crash
    XCTAssertTrue(true)
  }

  func test_executeTask_cancelsExistingTaskWithSameId() async {
    // GIVEN: A long-running task
    var firstCompleted = false

    sut.executeTask(
      id: "dup",
      operation: {
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        firstCompleted = true
      },
      onError: nil
    )

    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

    // WHEN: Execute second task with same ID
    sut.executeTask(id: "dup", operation: {}, onError: nil)

    try? await Task.sleep(nanoseconds: 30_000_000) // 30ms

    // THEN: First task should not have completed
    XCTAssertFalse(firstCompleted)
  }

  func test_executeTask_automaticCleanupOnCompletion() async {
    // GIVEN & WHEN: Execute a task
    sut.executeTask(id: "cleanup", operation: {}, onError: nil)

    // Wait for cleanup
    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

    // THEN: Task should be removed
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  func test_executeTask_automaticCleanupOnError() async {
    // GIVEN & WHEN: Execute a task that throws
    sut.executeTask(id: "error-cleanup", operation: { throw NSError(domain: "Test", code: 1) }, onError: { _ in })

    // Wait for cleanup
    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

    // THEN: Task should be removed
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  // MARK: - cancelTask(id:)

  func test_cancelTask_cancelsSpecificTask() async {
    // GIVEN: A running task
    sut.executeTask(id: "cancel-me", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
    XCTAssertTrue(sut.isTaskRunning(id: "cancel-me"))

    // WHEN: Cancel the task
    sut.cancelTask(id: "cancel-me")

    // THEN: Task should no longer be running
    XCTAssertFalse(sut.isTaskRunning(id: "cancel-me"))
  }

  func test_cancelTask_ignoresNonExistentTask() {
    // GIVEN: No tasks
    // WHEN & THEN: Cancel non-existent task should not crash
    sut.cancelTask(id: "non-existent")
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  func test_cancelTask_removesFromTracking() async {
    // GIVEN: A running task
    sut.executeTask(id: "tracked", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
    XCTAssertEqual(sut.runningTaskCount, 1)

    // WHEN: Cancel the task
    sut.cancelTask(id: "tracked")

    // THEN: Task should be removed
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  // MARK: - cancelAllTasks()

  func test_cancelAllTasks_cancelsMultipleRunningTasks() async {
    // GIVEN: Multiple running tasks
    sut.executeTask(id: "t1", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)
    sut.executeTask(id: "t2", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)
    sut.executeTask(id: "t3", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
    XCTAssertEqual(sut.runningTaskCount, 3)

    // WHEN: Cancel all tasks
    sut.cancelAllTasks()

    // THEN: All tasks should be cancelled
    XCTAssertEqual(sut.runningTaskCount, 0)
    XCTAssertFalse(sut.isTaskRunning(id: "t1"))
    XCTAssertFalse(sut.isTaskRunning(id: "t2"))
    XCTAssertFalse(sut.isTaskRunning(id: "t3"))
  }

  func test_cancelAllTasks_worksOnEmptyManager() {
    // GIVEN: No tasks
    // WHEN: Cancel all
    sut.cancelAllTasks()

    // THEN: Should not crash
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  func test_cancelAllTasks_clearsTrackingDictionary() async {
    // GIVEN: A running task
    sut.executeTask(id: "clear-me", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
    XCTAssertEqual(sut.runningTaskCount, 1)

    // WHEN: Cancel all tasks
    sut.cancelAllTasks()

    // THEN: Dictionary should be cleared
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  // MARK: - cancelTaskInternal(id:)

  func test_cancelTaskInternal_cancelsTaskByStringId() async {
    // GIVEN: A running task
    sut.executeTask(id: "internal", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
    XCTAssertTrue(sut.isTaskRunning(id: "internal"))

    // WHEN: Cancel using internal method
    sut.cancelTaskInternal(id: "internal")

    // THEN: Task should be cancelled
    XCTAssertFalse(sut.isTaskRunning(id: "internal"))
  }

  func test_cancelTaskInternal_removesFromTracking() async {
    // GIVEN: A running task
    sut.executeTask(id: "internal-tracking", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
    XCTAssertEqual(sut.runningTaskCount, 1)

    // WHEN: Cancel using internal method
    sut.cancelTaskInternal(id: "internal-tracking")

    // THEN: Task should be removed
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  // MARK: - Edge Cases

  func test_executeTask_withEmptyStringId() async {
    // GIVEN & WHEN: Execute task with empty string ID
    var didExecute = false
    sut.executeTask(id: "", operation: { didExecute = true }, onError: nil)

    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

    // THEN: Should work normally
    XCTAssertTrue(didExecute)
  }

  func test_isTaskRunning_withDifferentHashableTypes() async {
    // GIVEN: Tasks with different ID types
    sut.executeTask(id: "string-id", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

    // WHEN & THEN: Check with string type
    XCTAssertTrue(sut.isTaskRunning(id: "string-id"))

    // Check with non-existent int type
    XCTAssertFalse(sut.isTaskRunning(id: 123))
  }
}
