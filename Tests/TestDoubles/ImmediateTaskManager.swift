import Foundation
import Testing

@testable import ViewFeature

/// Test double that executes tasks immediately and synchronously.
///
/// `ImmediateTaskManager` is a test implementation of ``TaskExecuting`` that provides
/// deterministic, synchronous task execution for reliable testing. Unlike the production
/// ``TaskManager``, this implementation executes tasks immediately without asynchronous
/// scheduling, eliminating timing-related test flakiness.
///
/// ## Purpose
///
/// - **Deterministic testing**: Tasks execute immediately in a predictable order
/// - **No timing issues**: Eliminates race conditions and flaky tests
/// - **Fast test execution**: No actual async delays
/// - **Task verification**: Track which tasks were executed and cancelled
///
/// ## Usage
///
/// ```swift
/// @Test func loadDataExecutesTask() async {
///     // GIVEN: Store with ImmediateTaskManager
///     let taskManager = ImmediateTaskManager()
///     let store = Store(
///         initialState: MyFeature.State(),
///         feature: MyFeature(),
///         taskExecutor: taskManager
///     )
///
///     // WHEN: Send action that triggers a task
///     await store.send(.loadData).value
///
///     // THEN: Verify task was executed
///     #expect(taskManager.executedTasks.count == 1)
///     #expect(taskManager.executedTasks[0].id == "load-data")
///     #expect(taskManager.executedTasks[0].succeeded == true)
/// }
/// ```
///
/// ## Task Execution Model
///
/// - Tasks execute **immediately** when `executeTask` is called
/// - Tasks run **synchronously** (no actual async scheduling)
/// - Tasks complete **before** `executeTask` returns
/// - The returned `Task` is already completed
///
/// ## Tracking
///
/// The manager tracks:
/// - All executed tasks (with success/failure status)
/// - All cancelled task IDs
/// - Current "running" task count (always 0 due to immediate execution)
///
/// ## Example: Testing Error Handling
///
/// ```swift
/// @Test func errorHandlingWorks() async {
///     let taskManager = ImmediateTaskManager()
///     let store = Store(
///         initialState: MyFeature.State(),
///         feature: MyFeature(),
///         taskExecutor: taskManager
///     )
///
///     await store.send(.actionThatFails).value
///
///     // Verify task was executed but failed
///     #expect(taskManager.executedTasks.count == 1)
///     #expect(taskManager.executedTasks[0].succeeded == false)
///     #expect(store.state.errorMessage != nil)
/// }
/// ```
@MainActor
public final class ImmediateTaskManager: TaskExecuting {
    /// Record of an executed task with its outcome.
    public struct ExecutedTask {
        /// The task ID
        public let id: String
        /// Whether the task succeeded (true) or threw an error (false)
        public let succeeded: Bool
    }

    /// All tasks that were executed, in order.
    public private(set) var executedTasks: [ExecutedTask] = []

    /// All task IDs that were cancelled, in order.
    public private(set) var cancelledTaskIds: [String] = []

    public init() {}

    /// Executes a task immediately and synchronously.
    ///
    /// The task runs to completion before this method returns. The returned `Task`
    /// is already completed and can be awaited without delay.
    ///
    /// - Parameters:
    ///   - id: The task identifier
    ///   - operation: The operation to execute
    ///   - onError: Optional error handler
    /// - Returns: A completed Task
    public func executeTask(
        id: String,
        operation: @escaping () async throws -> Void,
        onError: ((Error) async -> Void)?
    ) -> Task<Void, Never> {
        Task {
            do {
                try await operation()
                executedTasks.append(ExecutedTask(id: id, succeeded: true))
            } catch {
                executedTasks.append(ExecutedTask(id: id, succeeded: false))
                await onError?(error)
            }
        }
    }

    /// Records the cancelled task IDs.
    ///
    /// - Parameter ids: The task IDs to cancel
    public func cancelTasks(ids: [String]) {
        cancelledTaskIds.append(contentsOf: ids)
    }

    /// Always returns 0 because tasks execute immediately.
    public var runningTaskCount: Int { 0 }

    /// Always returns false because tasks execute immediately.
    public func isTaskRunning<ID: TaskID>(id: ID) -> Bool { false }

    // MARK: - Test Helpers

    /// Resets all tracked tasks and cancellations.
    ///
    /// Useful for reusing the same manager across multiple test scenarios.
    public func reset() {
        executedTasks.removeAll()
        cancelledTaskIds.removeAll()
    }

    /// Asserts that a task with the given ID was executed.
    ///
    /// - Parameters:
    ///   - id: The task ID to check
    ///   - file: The file where the assertion is called (automatically populated)
    ///   - line: The line where the assertion is called (automatically populated)
    public func assertTaskExecuted(
        id: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let executed = executedTasks.contains { $0.id == id }
        #expect(executed, "Expected task '\(id)' to be executed", sourceLocation: SourceLocation(
            fileID: file.description,
            filePath: file.description,
            line: Int(line),
            column: 0
        ))
    }

    /// Asserts that a task with the given ID was executed and succeeded.
    ///
    /// - Parameters:
    ///   - id: The task ID to check
    ///   - file: The file where the assertion is called (automatically populated)
    ///   - line: The line where the assertion is called (automatically populated)
    public func assertTaskSucceeded(
        id: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let task = executedTasks.first(where: { $0.id == id }) else {
            Issue.record("Task '\(id)' was not executed", sourceLocation: SourceLocation(
                fileID: file.description,
                filePath: file.description,
                line: Int(line),
                column: 0
            ))
            return
        }

        #expect(task.succeeded, "Expected task '\(id)' to succeed", sourceLocation: SourceLocation(
            fileID: file.description,
            filePath: file.description,
            line: Int(line),
            column: 0
        ))
    }

    /// Asserts that a task with the given ID was executed and failed.
    ///
    /// - Parameters:
    ///   - id: The task ID to check
    ///   - file: The file where the assertion is called (automatically populated)
    ///   - line: The line where the assertion is called (automatically populated)
    public func assertTaskFailed(
        id: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let task = executedTasks.first(where: { $0.id == id }) else {
            Issue.record("Task '\(id)' was not executed", sourceLocation: SourceLocation(
                fileID: file.description,
                filePath: file.description,
                line: Int(line),
                column: 0
            ))
            return
        }

        #expect(!task.succeeded, "Expected task '\(id)' to fail", sourceLocation: SourceLocation(
            fileID: file.description,
            filePath: file.description,
            line: Int(line),
            column: 0
        ))
    }

    /// Asserts that a task with the given ID was cancelled.
    ///
    /// - Parameters:
    ///   - id: The task ID to check
    ///   - file: The file where the assertion is called (automatically populated)
    ///   - line: The line where the assertion is called (automatically populated)
    public func assertTaskCancelled(
        id: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let cancelled = cancelledTaskIds.contains(id)
        #expect(cancelled, "Expected task '\(id)' to be cancelled", sourceLocation: SourceLocation(
            fileID: file.description,
            filePath: file.description,
            line: Int(line),
            column: 0
        ))
    }
}
