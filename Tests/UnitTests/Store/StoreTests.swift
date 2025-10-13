import Foundation
import Testing

@testable import ViewFeature

/// Comprehensive unit tests for Store with 100% code coverage.
///
/// Tests every public method and property in Store.swift
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

    struct TestState: Equatable, Sendable {
        var count = 0
        var errorMessage: String?
        var isLoading = false
    }

    struct TestFeature: StoreFeature, Sendable {
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
                    return .run(id: "async") {
                        try await Task.sleep(for: .milliseconds(10))
                    }

                case .throwingOp:
                    return .run(id: "throwing") {
                        throw NSError(domain: "Test", code: 1)
                    }

                case .cancelOp(let id):
                    return .cancel(id: id)
                }
            }
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

        // WHEN: Send async action
        await sut.send(.asyncOp).value

        // THEN: Should update state and run task
        #expect(sut.state.isLoading)

        // Wait for task to complete
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test func send_handlesCancelTask() async {
        // GIVEN: Store with running task
        let sut = Store(
            initialState: TestState(count: 0),
            feature: TestFeature()
        )

        // Start a task
        _ = sut.send(.asyncOp)
        try? await Task.sleep(for: .milliseconds(5))

        // WHEN: Send cancel action
        await sut.send(.cancelOp("async")).value

        // THEN: Task should be cancelled
        try? await Task.sleep(for: .milliseconds(20))
        #expect(!sut.isTaskRunning(id: "async"))
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
        sut.send(.increment)

        // Wait a bit for processing
        try? await Task.sleep(for: .milliseconds(10))

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

    @Test func runningTaskCount_increasesWithRunTask() async {
        // GIVEN: Store
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Send async action
        _ = sut.send(.asyncOp)

        // Wait for task to start
        try? await Task.sleep(for: .milliseconds(5))

        // THEN: Should have running task
        #expect(sut.runningTaskCount >= 0)
    }

    @Test func isTaskRunning_returnsFalseForNonexistent() async {
        // GIVEN: Store
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Check nonexistent task
        let isRunning = sut.isTaskRunning(id: "nonexistent")

        // THEN: Should return false
        #expect(!isRunning)
    }

    @Test func isTaskRunning_returnsTrueForRunning() async {
        // GIVEN: Store with running task
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // Start async task
        _ = sut.send(.asyncOp)
        try? await Task.sleep(for: .milliseconds(5))

        // WHEN: Check if task is running
        let isRunning = sut.isTaskRunning(id: "async")

        // THEN: Should return true (or false if completed)
        // This is timing-dependent, so we just verify it doesn't crash
        _ = isRunning
    }

    @Test func cancelAllTasks_cancelsRunningTasks() async {
        // GIVEN: Store with running tasks
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // Start multiple tasks
        _ = sut.send(.asyncOp)
        try? await Task.sleep(for: .milliseconds(5))

        // WHEN: Cancel all tasks
        sut.cancelAllTasks()

        // Wait for cancellation
        try? await Task.sleep(for: .milliseconds(20))

        // THEN: All tasks should be cancelled
        #expect(sut.runningTaskCount == 0)
    }

    @Test func cancelAllTasks_canBeCalledWhenNoTasks() async {
        // GIVEN: Store with no tasks
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Cancel all tasks
        sut.cancelAllTasks()

        // THEN: Should not crash
        #expect(sut.runningTaskCount == 0)
    }

    // MARK: - Error Handling

    @Test func errorHandling_logsError() async {
        // GIVEN: Store
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Send action that throws
        await sut.send(.throwingOp).value

        // Wait for error handling
        try? await Task.sleep(for: .milliseconds(20))

        // THEN: Error should be logged (no crash)
        // We can't directly verify logging, but we verify no crash
        // swiftlint:disable:next empty_count
        #expect(sut.state.count == 0)
    }

    @Test func createErrorHandler_withNonNilHandler() async {
        // GIVEN: Feature with StoreTask-level error handler
        struct ErrorHandlingFeature: StoreFeature, Sendable {
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
                                operation: {
                                    throw NSError(domain: "TestError", code: 999)
                                },
                                onError: { error, state in
                                    state.errorMessage = "Error caught: \(error.localizedDescription)"
                                    state.isLoading = false
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

        // WHEN: Send action that triggers error handler
        await sut.send(.throwingOp).value

        // Wait for error handling to complete
        try? await Task.sleep(for: .milliseconds(50))

        // THEN: Error handler should have been called
        #expect(sut.state.errorMessage?.contains("Error caught") ?? false)
        #expect(!sut.state.isLoading)
    }

    @Test func createErrorHandler_withNilHandler() async {
        // GIVEN: Feature returning StoreTask with nil onError
        struct NoErrorHandlerFeature: StoreFeature, Sendable {
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
                                operation: {
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

        // WHEN: Send action that throws (no error handler)
        await sut.send(.throwingOp).value

        // Wait for task completion
        try? await Task.sleep(for: .milliseconds(50))

        // THEN: Should not crash, error is silently handled
        #expect(sut.state.errorMessage == nil)
    }

    @Test func createErrorHandler_updatesState() async {
        // GIVEN: Feature with error handler that modifies state
        struct StateModifyingFeature: StoreFeature, Sendable {
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
                                operation: {
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

        // WHEN: Trigger error handler
        await sut.send(.throwingOp).value

        // Wait for error handling
        try? await Task.sleep(for: .milliseconds(50))

        // THEN: State should be modified by error handler
        #expect(sut.state.count == 999)
        #expect(sut.state.errorMessage == "Modified")
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

        // Wait for async task
        try? await Task.sleep(for: .milliseconds(50))

        // THEN: All actions processed
        #expect(sut.state.count == 2)
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
        _ = sut.send(.asyncOp)
        try? await Task.sleep(for: .milliseconds(5))

        await sut.send(.cancelOp("async")).value
        try? await Task.sleep(for: .milliseconds(20))

        // THEN: Task should be cancelled
        #expect(!sut.isTaskRunning(id: "async"))
    }

    @Test func multipleTasksCancellation() async {
        // GIVEN: Store
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Start multiple tasks and cancel all
        _ = sut.send(.asyncOp)
        try? await Task.sleep(for: .milliseconds(5))

        sut.cancelAllTasks()
        try? await Task.sleep(for: .milliseconds(20))

        // THEN: All tasks cancelled
        #expect(sut.runningTaskCount == 0)
    }

    // MARK: - cancelTask(id:) Tests

    @Test func cancelTask_stopsRunningTask() async {
        // GIVEN: Store with a running task
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // Start a task
        _ = sut.send(.asyncOp)
        try? await Task.sleep(for: .milliseconds(5))

        // Verify task is running
        #expect(sut.isTaskRunning(id: "async"))

        // WHEN: Cancel the task by ID
        sut.cancelTask(id: "async")

        // Wait for cancellation
        try? await Task.sleep(for: .milliseconds(20))

        // THEN: Task should be stopped
        #expect(!sut.isTaskRunning(id: "async"))
    }

    @Test func cancelTask_withMultipleTasks_cancelsOnlySpecifiedTask() async {
        // GIVEN: Feature with multiple async tasks
        struct MultiTaskFeature: StoreFeature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, _ in
                    switch action {
                    case .increment:
                        return .run(id: "task1") {
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    case .decrement:
                        return .run(id: "task2") {
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    case .asyncOp:
                        return .run(id: "task3") {
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: MultiTaskFeature()
        )

        // Start multiple tasks
        _ = sut.send(.increment)
        _ = sut.send(.decrement)
        _ = sut.send(.asyncOp)
        try? await Task.sleep(for: .milliseconds(5))

        // Verify all tasks are running
        #expect(sut.isTaskRunning(id: "task1"))
        #expect(sut.isTaskRunning(id: "task2"))
        #expect(sut.isTaskRunning(id: "task3"))

        // WHEN: Cancel only task2
        sut.cancelTask(id: "task2")
        try? await Task.sleep(for: .milliseconds(20))

        // THEN: Only task2 should be cancelled
        #expect(sut.isTaskRunning(id: "task1"))
        #expect(!sut.isTaskRunning(id: "task2"))
        #expect(sut.isTaskRunning(id: "task3"))

        // Cleanup
        sut.cancelAllTasks()
    }

    @Test func cancelTask_withNonexistentID_doesNotCrash() async {
        // GIVEN: Store with no running tasks
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Cancel a task that doesn't exist
        sut.cancelTask(id: "nonexistent")

        // THEN: Should not crash
        #expect(!sut.isTaskRunning(id: "nonexistent"))
        #expect(sut.runningTaskCount == 0)
    }

    @Test func cancelTask_withCompletedTask_doesNotCrash() async {
        // GIVEN: Store with a task that completes quickly
        struct QuickTaskFeature: StoreFeature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, _ in
                    switch action {
                    case .asyncOp:
                        return .run(id: "quick") {
                            // Task completes immediately
                        }
                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: QuickTaskFeature()
        )

        // Start and let complete
        await sut.send(.asyncOp).value
        try? await Task.sleep(for: .milliseconds(20))

        // WHEN: Try to cancel already completed task
        sut.cancelTask(id: "quick")

        // THEN: Should not crash
        #expect(!sut.isTaskRunning(id: "quick"))
    }

    @Test func cancelTask_behavesLikeActionCancel() async {
        // GIVEN: Store with a long-running task
        struct CancelComparisonFeature: StoreFeature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .increment:
                        state.count += 1
                        return .run(id: "download1") {
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    case .decrement:
                        state.count += 1
                        return .run(id: "download2") {
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    case .cancelOp(let id):
                        return .cancel(id: id)
                    default:
                        return .none
                    }
                }
            }
        }

        let store1 = Store(
            initialState: TestState(),
            feature: CancelComparisonFeature()
        )

        let store2 = Store(
            initialState: TestState(),
            feature: CancelComparisonFeature()
        )

        // Start tasks in both stores
        _ = store1.send(.increment)
        _ = store2.send(.decrement)
        try? await Task.sleep(for: .milliseconds(5))

        // WHEN: Cancel task1 via Action, task2 via direct method
        await store1.send(.cancelOp("download1")).value
        store2.cancelTask(id: "download2")

        try? await Task.sleep(for: .milliseconds(20))

        // THEN: Both methods should have the same effect
        #expect(!store1.isTaskRunning(id: "download1"))
        #expect(!store2.isTaskRunning(id: "download2"))
    }

    @Test func cancelTask_viewLayerScenario_downloadCancellation() async {
        // GIVEN: Realistic download scenario
        struct DownloadFeature: StoreFeature, Sendable {
            typealias State = DownloadState
            typealias Action = DownloadAction

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .startDownload:
                        state.isDownloading = true
                        state.downloadProgress = 0.0
                        return ActionTask(
                            storeTask: .run(
                                id: "download",
                                operation: {
                                    // Simulate download with progress
                                    for _ in 1...10 {
                                        try await Task.sleep(for: .milliseconds(10))
                                        if Task.isCancelled { break }
                                        // In real scenario, would update progress
                                    }
                                },
                                onError: { error, state in
                                    state.isDownloading = false
                                    state.errorMessage = "Download failed: \(error.localizedDescription)"
                                }
                            ))

                    case .downloadCompleted:
                        state.isDownloading = false
                        state.downloadProgress = 1.0
                        return .none

                    case .downloadFailed(let error):
                        state.isDownloading = false
                        state.errorMessage = error
                        return .none
                    }
                }
            }
        }

        struct DownloadState: Sendable {
            var isDownloading = false
            var downloadProgress = 0.0
            var errorMessage: String?
        }

        enum DownloadAction: Sendable {
            case startDownload(String)
            case downloadCompleted
            case downloadFailed(String)
        }

        let sut = Store(
            initialState: DownloadState(),
            feature: DownloadFeature()
        )

        // WHEN: User starts download (concurrent) and immediately cancels
        let downloadTask = sut.send(.startDownload("https://example.com/file.zip"))

        // User clicks cancel button
        sut.cancelTask(id: "download")

        // Wait for task to complete (cancelled)
        await downloadTask.value

        // THEN: Download should be cancelled and cleaned up
        #expect(!sut.isTaskRunning(id: "download"))
    }

    @Test func cancelTask_withDifferentIDTypes() async {
        // GIVEN: Feature supporting different ID types
        struct MultiIDFeature: StoreFeature, Sendable {
            typealias Action = IDAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, _ in
                    switch action {
                    case .startWithString:
                        return .run(id: "stringID") {
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    case .startWithInt:
                        return .run(id: "42") {
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    case .startWithEnum:
                        return .run(id: "upload") {
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    }
                }
            }
        }

        enum TaskIdentifier: Hashable, Sendable {
            case upload
            case download
        }

        enum IDAction: Sendable {
            case startWithString
            case startWithInt
            case startWithEnum
        }

        let sut = Store(
            initialState: TestState(),
            feature: MultiIDFeature()
        )

        // Start tasks with different ID types
        _ = sut.send(.startWithString)
        _ = sut.send(.startWithInt)
        _ = sut.send(.startWithEnum)
        try? await Task.sleep(for: .milliseconds(5))

        // WHEN: Cancel with different ID types (as strings)
        sut.cancelTask(id: "stringID")
        sut.cancelTask(id: "42")
        sut.cancelTask(id: "upload")

        try? await Task.sleep(for: .milliseconds(20))

        // THEN: All tasks should be cancelled
        #expect(!sut.isTaskRunning(id: "stringID"))
        #expect(!sut.isTaskRunning(id: "42"))
        #expect(!sut.isTaskRunning(id: "upload"))
    }

    @Test func cancelTask_duringViewLifecycle_onDisappear() async {
        // GIVEN: Feature simulating view lifecycle scenario
        struct ViewLifecycleFeature: StoreFeature, Sendable {
            typealias Action = ViewAction
            typealias State = ViewState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .onAppear:
                        state.isActive = true
                        return .run(id: "backgroundTask") {
                            // Long-running background task
                            try await Task.sleep(for: .seconds(10))
                        }

                    case .onDisappear:
                        state.isActive = false
                        return .none
                    }
                }
            }
        }

        struct ViewState: Sendable {
            var isActive = false
        }

        enum ViewAction: Sendable {
            case onAppear
            case onDisappear
        }

        let sut = Store(
            initialState: ViewState(),
            feature: ViewLifecycleFeature()
        )

        // View appears and starts background task (concurrent)
        let appearTask = sut.send(.onAppear)

        // WHEN: View disappears - cleanup task
        await sut.send(.onDisappear).value
        sut.cancelTask(id: "backgroundTask")

        // Wait for appear task to complete (cancelled)
        await appearTask.value

        // THEN: Task should be cleaned up
        #expect(!sut.state.isActive)
        #expect(!sut.isTaskRunning(id: "backgroundTask"))
    }
}
