import Foundation
import Testing

@testable import ViewFeature

/// Comprehensive unit tests for TaskManager with 100% code coverage.
///
/// Tests every public method, property, and code path in TaskManager.swift
@MainActor
@Suite struct TaskManagerTests {
    // MARK: - init()

    @Test func init_createsEmptyManager() {
        let sut = TaskManager()
        // GIVEN & WHEN: TaskManager created in setUp
        // THEN: It should have no running tasks
        #expect(sut.runningTaskCount == 0)
    }

    // MARK: - runningTaskCount

    @Test func runningTaskCount_returnsZeroInitially() {
        let sut = TaskManager()
        // GIVEN & WHEN: Fresh TaskManager
        // THEN: Count should be zero
        #expect(sut.runningTaskCount == 0)
    }

    @Test func runningTaskCount_reflectsActiveTasks() async {
        let sut = TaskManager()
        // GIVEN: Execute multiple tasks
        sut.executeTask(
            id: "task-1", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)
        sut.executeTask(
            id: "task-2", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

        // Wait for tasks to start
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        // THEN: Count should reflect active tasks
        #expect(sut.runningTaskCount == 2)
    }

    @Test func runningTaskCount_decreasesAfterCompletion() async {
        let sut = TaskManager()
        // GIVEN: Execute a quick task
        sut.executeTask(id: "temp", operation: {}, onError: nil)

        // Wait for completion
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // THEN: Count should be zero
        #expect(sut.runningTaskCount == 0)
    }

    // MARK: - isTaskRunning(id:)

    @Test func isTaskRunning_returnsTrueForRunningTask() async {
        let sut = TaskManager()
        // GIVEN: A running task
        sut.executeTask(
            id: "running", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        // WHEN & THEN: Check if task is running
        #expect(sut.isTaskRunning(id: "running"))
    }

    @Test func isTaskRunning_returnsFalseForNonExistentTask() {
        let sut = TaskManager()
        // GIVEN: No tasks
        // WHEN & THEN: Check for non-existent task
        #expect(!sut.isTaskRunning(id: "non-existent"))
    }

    @Test func isTaskRunning_returnsFalseAfterCompletion() async {
        let sut = TaskManager()
        // GIVEN: Execute a quick task
        sut.executeTask(id: "completed", operation: {}, onError: nil)

        // Wait for completion
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // THEN: Should return false
        #expect(!sut.isTaskRunning(id: "completed"))
    }

    // MARK: - executeTask(id:operation:onError:)

    @Test func executeTask_executesOperationSuccessfully() async {
        let sut = TaskManager()
        // GIVEN: A flag
        var didExecute = false

        // WHEN: Execute a task
        sut.executeTask(id: "test", operation: { didExecute = true }, onError: nil)

        // Wait for execution
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // THEN: Operation should have executed
        #expect(didExecute)
    }

    @Test func executeTask_callsErrorHandlerOnFailure() async {
        let sut = TaskManager()
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
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // THEN: Error handler should have been called
        #expect(capturedError != nil)
    }

    @Test func executeTask_doesNotCrashWhenNilErrorHandler() async {
        let sut = TaskManager()
        // GIVEN & WHEN: Execute a task that throws with nil handler
        sut.executeTask(
            id: "no-handler", operation: { throw NSError(domain: "Test", code: 1) }, onError: nil)

        // Wait
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // THEN: Should not crash
        #expect(true)
    }

    @Test func executeTask_cancelsExistingTaskWithSameId() async {
        let sut = TaskManager()
        // GIVEN: A long-running task
        var firstCompleted = false

        sut.executeTask(
            id: "dup",
            operation: {
                try await Task.sleep(nanoseconds: 200_000_000)  // 200ms
                firstCompleted = true
            },
            onError: nil
        )

        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        // WHEN: Execute second task with same ID
        sut.executeTask(id: "dup", operation: {}, onError: nil)

        try? await Task.sleep(nanoseconds: 30_000_000)  // 30ms

        // THEN: First task should not have completed
        #expect(!firstCompleted)
    }

    @Test func executeTask_automaticCleanupOnCompletion() async {
        let sut = TaskManager()
        // GIVEN & WHEN: Execute a task
        sut.executeTask(id: "cleanup", operation: {}, onError: nil)

        // Wait for cleanup
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // THEN: Task should be removed
        #expect(sut.runningTaskCount == 0)
    }

    @Test func executeTask_automaticCleanupOnError() async {
        let sut = TaskManager()
        // GIVEN & WHEN: Execute a task that throws
        sut.executeTask(
            id: "error-cleanup", operation: { throw NSError(domain: "Test", code: 1) }, onError: { _ in })

        // Wait for cleanup
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // THEN: Task should be removed
        #expect(sut.runningTaskCount == 0)
    }

    // MARK: - cancelTask(id:)

    @Test func cancelTask_cancelsSpecificTask() async {
        let sut = TaskManager()
        // GIVEN: A running task
        sut.executeTask(
            id: "cancel-me", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        #expect(sut.isTaskRunning(id: "cancel-me"))

        // WHEN: Cancel the task
        sut.cancelTask(id: "cancel-me")

        // THEN: Task should no longer be running
        #expect(!sut.isTaskRunning(id: "cancel-me"))
    }

    @Test func cancelTask_ignoresNonExistentTask() {
        let sut = TaskManager()
        // GIVEN: No tasks
        // WHEN & THEN: Cancel non-existent task should not crash
        sut.cancelTask(id: "non-existent")
        #expect(sut.runningTaskCount == 0)
    }

    @Test func cancelTask_removesFromTracking() async {
        let sut = TaskManager()
        // GIVEN: A running task
        sut.executeTask(
            id: "tracked", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        #expect(sut.runningTaskCount == 1)

        // WHEN: Cancel the task
        sut.cancelTask(id: "tracked")

        // THEN: Task should be removed
        #expect(sut.runningTaskCount == 0)
    }

    // MARK: - cancelAllTasks()

    @Test func cancelAllTasks_cancelsMultipleRunningTasks() async {
        let sut = TaskManager()
        // GIVEN: Multiple running tasks
        sut.executeTask(
            id: "t1", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)
        sut.executeTask(
            id: "t2", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)
        sut.executeTask(
            id: "t3", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        #expect(sut.runningTaskCount == 3)

        // WHEN: Cancel all tasks
        sut.cancelAllTasks()

        // THEN: All tasks should be cancelled
        #expect(sut.runningTaskCount == 0)
        #expect(!sut.isTaskRunning(id: "t1"))
        #expect(!sut.isTaskRunning(id: "t2"))
        #expect(!sut.isTaskRunning(id: "t3"))
    }

    @Test func cancelAllTasks_worksOnEmptyManager() {
        let sut = TaskManager()
        // GIVEN: No tasks
        // WHEN: Cancel all
        sut.cancelAllTasks()

        // THEN: Should not crash
        #expect(sut.runningTaskCount == 0)
    }

    @Test func cancelAllTasks_clearsTrackingDictionary() async {
        let sut = TaskManager()
        // GIVEN: A running task
        sut.executeTask(
            id: "clear-me", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        #expect(sut.runningTaskCount == 1)

        // WHEN: Cancel all tasks
        sut.cancelAllTasks()

        // THEN: Dictionary should be cleared
        #expect(sut.runningTaskCount == 0)
    }

    // MARK: - cancelTaskInternal(id:)

    @Test func cancelTaskInternal_cancelsTaskByStringId() async {
        let sut = TaskManager()
        // GIVEN: A running task
        sut.executeTask(
            id: "internal", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        #expect(sut.isTaskRunning(id: "internal"))

        // WHEN: Cancel using internal method
        sut.cancelTaskInternal(id: "internal")

        // THEN: Task should be cancelled
        #expect(!sut.isTaskRunning(id: "internal"))
    }

    @Test func cancelTaskInternal_removesFromTracking() async {
        let sut = TaskManager()
        // GIVEN: A running task
        sut.executeTask(
            id: "internal-tracking", operation: { try await Task.sleep(nanoseconds: 100_000_000) },
            onError: nil)

        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        #expect(sut.runningTaskCount == 1)

        // WHEN: Cancel using internal method
        sut.cancelTaskInternal(id: "internal-tracking")

        // THEN: Task should be removed
        #expect(sut.runningTaskCount == 0)
    }

    // MARK: - Edge Cases

    @Test func executeTask_withEmptyStringId() async {
        let sut = TaskManager()
        // GIVEN & WHEN: Execute task with empty string ID
        var didExecute = false
        sut.executeTask(id: "", operation: { didExecute = true }, onError: nil)

        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // THEN: Should work normally
        #expect(didExecute)
    }

    @Test func isTaskRunning_withDifferentHashableTypes() async {
        let sut = TaskManager()
        // GIVEN: Tasks with different ID types
        sut.executeTask(
            id: "string-id", operation: { try await Task.sleep(nanoseconds: 100_000_000) }, onError: nil)

        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        // WHEN & THEN: Check with string type
        #expect(sut.isTaskRunning(id: "string-id"))

        // Check with non-existent int type
        #expect(!sut.isTaskRunning(id: 123))
    }
}
