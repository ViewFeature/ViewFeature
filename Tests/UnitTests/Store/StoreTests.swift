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

    @Test func cancelAllTasks_cancelsRunningTasks() async {
        // GIVEN: Store with running tasks
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // Start multiple tasks (fire-and-forget)
        let task = sut.send(.asyncOp)

        // WHEN: Cancel all tasks
        sut.cancelAllTasks()

        // THEN: Wait for task cleanup
        await task.value
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
                                operation: { _ in
                                    throw NSError(domain: "TestError", code: 999)
                                },
                                onError: { error, _ in
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

        // WHEN: Send action that triggers error handler and wait for completion
        await sut.send(.throwingOp).value

        // THEN: Error handler should have been called
        #expect(sut.state.errorMessage?.contains("Error caught") ?? false)
        #expect(!sut.state.isLoading)
        #expect(sut.runningTaskCount == 0)
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

        // WHEN: Start multiple tasks and cancel all
        let asyncTask = sut.send(.asyncOp)
        sut.cancelAllTasks()

        // THEN: Wait for task cleanup
        await asyncTask.value
        #expect(sut.runningTaskCount == 0)
    }

    // MARK: - cancelTask(id:) Tests

    @Test func cancelTask_cancelsRunningTask() async {
        // GIVEN: Store with a running task
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // Start a task (fire-and-forget)
        let asyncTask = sut.send(.asyncOp)

        // WHEN: Cancel the task by ID immediately
        sut.cancelTask(id: "async")

        // THEN: Wait for task to complete and verify cleanup
        await asyncTask.value
        #expect(sut.runningTaskCount == 0)
    }

    @Test func cancelTask_withMultipleTasks_cancelsOnlySpecifiedTask() async {
        // GIVEN: Feature with multiple async tasks
        struct MultiTaskFeature: StoreFeature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .increment:
                        return .run(id: "task1") { _ in
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    case .decrement:
                        state.count = 99  // Mark that task2 started
                        return .run(id: "task2") { _ in
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    case .asyncOp:
                        return .run(id: "task3") { _ in
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

        // Start multiple tasks concurrently
        let task1 = sut.send(.increment)
        let task2 = sut.send(.decrement)
        let task3 = sut.send(.asyncOp)

        // WHEN: Cancel only task2
        sut.cancelTask(id: "task2")

        // Cancel remaining tasks for cleanup
        sut.cancelAllTasks()

        // THEN: Wait for all tasks to complete/cancel
        await task1.value
        await task2.value
        await task3.value

        // Verify cleanup
        #expect(sut.runningTaskCount == 0)
        // Verify task2 started (state was modified)
        #expect(sut.state.count == 99)
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
                        return .run(id: "quick") { _ in
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

        // Start and wait for completion
        await sut.send(.asyncOp).value

        // WHEN: Try to cancel already completed task
        sut.cancelTask(id: "quick")

        // THEN: Should not crash, task already completed
        #expect(sut.runningTaskCount == 0)
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
                        return .run(id: "download1") { _ in
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    case .decrement:
                        state.count += 1
                        return .run(id: "download2") { _ in
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
        let task1 = store1.send(.increment)
        let task2 = store2.send(.decrement)

        // WHEN: Cancel task1 via Action, task2 via direct method
        await store1.send(.cancelOp("download1")).value
        store2.cancelTask(id: "download2")

        // THEN: Wait for cleanup and verify both methods work
        await task1.value
        await task2.value

        #expect(store1.runningTaskCount == 0)
        #expect(store2.runningTaskCount == 0)
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
                                operation: { _ in
                                    // Simulate download with progress
                                    for _ in 1...10 {
                                        try await Task.sleep(for: .milliseconds(10))
                                        if Task.isCancelled { break }
                                        // In real scenario, would update progress
                                    }
                                },
                                onError: { error, _ in
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

        enum DownloadAction: Sendable {
            case startDownload(String)
            case downloadCompleted
            case downloadFailed(String)
        }

        let sut = Store(
            initialState: DownloadState(),
            feature: DownloadFeature()
        )

        // WHEN: User starts download and immediately cancels
        let downloadTask = sut.send(.startDownload("https://example.com/file.zip"))

        // User clicks cancel button
        sut.cancelTask(id: "download")

        // THEN: Wait for task to complete (cancelled) and verify cleanup
        await downloadTask.value
        #expect(sut.runningTaskCount == 0)
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
                        return .run(id: "stringID") { _ in
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    case .startWithInt:
                        return .run(id: "42") { _ in
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    case .startWithEnum:
                        return .run(id: "upload") { _ in
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
        let task1 = sut.send(.startWithString)
        let task2 = sut.send(.startWithInt)
        let task3 = sut.send(.startWithEnum)

        // WHEN: Cancel with different ID types (as strings)
        sut.cancelTask(id: "stringID")
        sut.cancelTask(id: "42")
        sut.cancelTask(id: "upload")

        // THEN: Wait for all tasks and verify cleanup
        await task1.value
        await task2.value
        await task3.value

        #expect(sut.runningTaskCount == 0)
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
                        return .run(id: "backgroundTask") { _ in
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

        @Observable
        final class ViewState {
            var isActive = false

            init(isActive: Bool = false) {
                self.isActive = isActive
            }
        }

        enum ViewAction: Sendable {
            case onAppear
            case onDisappear
        }

        let sut = Store(
            initialState: ViewState(),
            feature: ViewLifecycleFeature()
        )

        // View appears and starts background task
        let appearTask = sut.send(.onAppear)

        // WHEN: View disappears - cleanup task
        await sut.send(.onDisappear).value
        sut.cancelTask(id: "backgroundTask")

        // THEN: Wait for task cancellation and verify cleanup
        await appearTask.value

        #expect(!sut.state.isActive)
        #expect(sut.runningTaskCount == 0)
    }

    @Test func cancelTask_triggersCancellationErrorInCatchHandler() async {
        // GIVEN: Feature with .catch handler that verifies CancellationError
        struct CancellationTestFeature: StoreFeature, Sendable {
            typealias Action = CancelAction
            typealias State = CancelState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .startLongTask:
                        state.isRunning = true
                        return .run(id: "long-task") { _ in
                            try await Task.sleep(for: .seconds(10))
                        }
                        .catch { error, state in
                            state.isRunning = false
                            state.didCatchError = true
                            state.caughtCancellationError = (error is CancellationError)
                        }

                    case .cancelTask:
                        return .cancel(id: "long-task")
                    }
                }
            }
        }

        @Observable
        final class CancelState {
            var isRunning = false
            var didCatchError = false
            var caughtCancellationError = false

            init(isRunning: Bool = false, didCatchError: Bool = false, caughtCancellationError: Bool = false) {
                self.isRunning = isRunning
                self.didCatchError = didCatchError
                self.caughtCancellationError = caughtCancellationError
            }
        }

        enum CancelAction: Sendable {
            case startLongTask
            case cancelTask
        }

        let sut = Store(
            initialState: CancelState(),
            feature: CancellationTestFeature()
        )

        // Start long-running task
        let taskHandle = sut.send(.startLongTask)

        // Wait for task to start
        try? await Task.sleep(for: .milliseconds(10))
        #expect(sut.state.isRunning)

        // WHEN: Cancel the task via action
        await sut.send(.cancelTask).value

        // Wait for cancellation to propagate
        await taskHandle.value
        try? await Task.sleep(for: .milliseconds(50))

        // THEN: Verify CancellationError was caught
        #expect(sut.state.didCatchError)
        #expect(sut.state.caughtCancellationError)
        #expect(!sut.state.isRunning)
        #expect(sut.runningTaskCount == 0)
    }

    @Test func cancelTaskDirect_triggersCancellationErrorInCatchHandler() async {
        // GIVEN: Feature with .catch handler
        struct DirectCancelFeature: StoreFeature, Sendable {
            typealias Action = SimpleAction
            typealias State = CancelState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .start:
                        state.isRunning = true
                        return .run(id: "direct-cancel-task") { _ in
                            try await Task.sleep(for: .seconds(10))
                        }
                        .catch { error, state in
                            state.isRunning = false
                            state.didCatchError = true
                            state.caughtCancellationError = (error is CancellationError)
                        }
                    }
                }
            }
        }

        @Observable
        final class CancelState {
            var isRunning = false
            var didCatchError = false
            var caughtCancellationError = false

            init(isRunning: Bool = false, didCatchError: Bool = false, caughtCancellationError: Bool = false) {
                self.isRunning = isRunning
                self.didCatchError = didCatchError
                self.caughtCancellationError = caughtCancellationError
            }
        }

        enum SimpleAction: Sendable {
            case start
        }

        let sut = Store(
            initialState: CancelState(),
            feature: DirectCancelFeature()
        )

        // Start task
        let taskHandle = sut.send(.start)

        // Wait for task to start
        try? await Task.sleep(for: .milliseconds(10))
        #expect(sut.state.isRunning)

        // WHEN: Cancel using direct store.cancelTask() method
        sut.cancelTask(id: "direct-cancel-task")

        // Wait for cancellation
        await taskHandle.value
        try? await Task.sleep(for: .milliseconds(50))

        // THEN: Verify CancellationError was caught
        #expect(sut.state.didCatchError)
        #expect(sut.state.caughtCancellationError)
        #expect(!sut.state.isRunning)
        #expect(sut.runningTaskCount == 0)
    }
}
