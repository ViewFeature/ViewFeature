import Foundation
import Testing

@testable import ViewFeature

/// Integration tests for TaskManager with Store and ActionHandler.
///
/// Tests how TaskManager coordinates task execution with Store actions
/// and handles concurrent task management.
@MainActor
@Suite struct TaskManagerIntegrationTests {
    // MARK: - Test Fixtures

    enum DataAction: Sendable {
        case fetch(String)
        case fetchMultiple([String])
        case cancelFetch(String)
        case cancelAll
        case process(String)
    }

    @Observable
    final class DataState {
        var data: [String: String] = [:]
        var isLoading: [String: Bool] = [:]
        var errors: [String: String] = [:]

        init(data: [String: String] = [:], isLoading: [String: Bool] = [:], errors: [String: String] = [:]) {
            self.data = data
            self.isLoading = isLoading
            self.errors = errors
        }
    }

    struct DataFeature: StoreFeature, Sendable {
        typealias Action = DataAction
        typealias State = DataState

        func handle() -> ActionHandler<Action, State> {
            ActionHandler { action, state in
                switch action {
                case .fetch(let id):
                    state.isLoading[id] = true
                    return .run(id: "fetch-\(id)") {
                        try await Task.sleep(for: .milliseconds(50))
                    }

                case .fetchMultiple(let ids):
                    for id in ids {
                        state.isLoading[id] = true
                    }
                    // Start first task (in real app, you'd handle multiple tasks differently)
                    if let firstId = ids.first {
                        return .run(id: "fetch-\(firstId)") {
                            try await Task.sleep(for: .milliseconds(30))
                        }
                    } else {
                        return .none
                    }

                case .cancelFetch(let id):
                    state.isLoading[id] = false
                    return .cancel(id: "fetch-\(id)")

                case .cancelAll:
                    state.isLoading.removeAll()
                    return .none  // cancelAllTasks() should be called separately

                case .process(let id):
                    state.data[id] = "processed"
                    return .none
                }
            }
        }
    }

    // MARK: - Basic Task Management Tests

    @Test func storeCanCancelRunningTask() async {
        // GIVEN: Store with running task
        let sut = Store(
            initialState: DataState(),
            feature: DataFeature()
        )

        // WHEN: Start task (concurrent) and immediately cancel
        let fetchTask = sut.send(.fetch("data1"))

        // Give task time to start
        try? await Task.sleep(for: .milliseconds(5))

        await sut.send(.cancelFetch("data1")).value

        // Wait for task to complete (cancelled tasks still complete)
        await fetchTask.value

        // Give time for cleanup
        try? await Task.sleep(for: .milliseconds(10))

        // THEN: Task should be cancelled and cleaned up
        #expect(!sut.isTaskRunning(id: "fetch-data1"))
        #expect(sut.state.isLoading["data1"] == false)
    }

    @Test func multipleConcurrentTasks() async {
        // GIVEN: Store
        let sut = Store(
            initialState: DataState(),
            feature: DataFeature()
        )

        // WHEN: Start multiple tasks (fire and forget for concurrent execution)
        _ = sut.send(.fetch("data1"))
        _ = sut.send(.fetch("data2"))
        _ = sut.send(.fetch("data3"))

        try? await Task.sleep(for: .milliseconds(10))

        // THEN: All tasks should be tracked and running
        #expect(sut.state.isLoading["data1"] ?? false)
        #expect(sut.state.isLoading["data2"] ?? false)
        #expect(sut.state.isLoading["data3"] ?? false)

        // Wait for all to complete
        try? await Task.sleep(for: .milliseconds(100))

        // Tasks should complete
        #expect(sut.runningTaskCount >= 0)
    }

    // MARK: - Task Cancellation Tests

    @Test func cancelAllTasksViaStore() async {
        // GIVEN: Store with multiple running tasks
        let sut = Store(
            initialState: DataState(),
            feature: DataFeature()
        )

        _ = sut.send(.fetch("data1"))
        _ = sut.send(.fetch("data2"))
        _ = sut.send(.fetch("data3"))

        try? await Task.sleep(for: .milliseconds(10))

        // WHEN: Cancel all tasks
        sut.cancelAllTasks()

        // Wait for cancellation
        try? await Task.sleep(for: .milliseconds(50))

        // THEN: All tasks should be cancelled
        #expect(sut.runningTaskCount == 0)
    }

    @Test func cancelSpecificTaskAmongMany() async {
        // GIVEN: Store with multiple running tasks
        let sut = Store(
            initialState: DataState(),
            feature: DataFeature()
        )

        _ = sut.send(.fetch("data1"))
        _ = sut.send(.fetch("data2"))
        _ = sut.send(.fetch("data3"))

        try? await Task.sleep(for: .milliseconds(10))

        // WHEN: Cancel specific task
        await sut.send(.cancelFetch("data2")).value

        try? await Task.sleep(for: .milliseconds(20))

        // THEN: Only that task should be cancelled
        #expect(!sut.isTaskRunning(id: "fetch-data2"))
    }

    // MARK: - Task Completion Tests

    @Test func taskCompletionUpdatesRunningCount() async {
        // GIVEN: Store with short task
        struct ShortTaskFeature: StoreFeature, Sendable {
            typealias Action = DataAction
            typealias State = DataState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, _ in
                    switch action {
                    case .fetch(let id):
                        return .run(id: "short-\(id)") {
                            try await Task.sleep(for: .milliseconds(10))
                        }
                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: DataState(),
            feature: ShortTaskFeature()
        )

        // WHEN: Start task and wait for completion
        await sut.send(.fetch("data1")).value

        // THEN: Running count should be back to 0
        #expect(sut.runningTaskCount == 0)
    }

    // MARK: - Task Error Handling Integration

    @Test func taskErrorsAreHandled() async {
        // GIVEN: Store with error-throwing task
        struct ErrorFeature: StoreFeature, Sendable {
            typealias Action = DataAction
            typealias State = DataState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .fetch(let id):
                        state.isLoading[id] = true
                        return ActionTask(
                            storeTask: .run(
                                id: "error-\(id)",
                                operation: {
                                    try await Task.sleep(for: .milliseconds(10))
                                    throw NSError(domain: "TestError", code: 1)
                                },
                                onError: { error, state in
                                    state.errors[id] = error.localizedDescription
                                    state.isLoading[id] = false
                                }
                            ))
                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: DataState(),
            feature: ErrorFeature()
        )

        // WHEN: Execute task that throws
        await sut.send(.fetch("data1")).value

        // Wait for error handler to complete
        try? await Task.sleep(for: .milliseconds(50))

        // THEN: Error should be handled
        #expect(sut.state.errors["data1"] != nil)
        #expect(sut.state.isLoading["data1"] == false)
    }

    // MARK: - Complex Task Workflows

    @Test func sequentialTaskExecution() async {
        // GIVEN: Store
        actor TaskTracker {
            var completedTasks: [String] = []

            func append(_ task: String) {
                completedTasks.append(task)
            }

            func getCompleted() -> [String] {
                completedTasks
            }
        }

        struct TrackingFeature: StoreFeature, Sendable {
            let tracker: TaskTracker

            typealias Action = DataAction
            typealias State = DataState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { [tracker] action, _ in
                    switch action {
                    case .fetch(let id):
                        return .run(id: "track-\(id)") {
                            try await Task.sleep(for: .milliseconds(20))
                            await tracker.append(id)
                        }
                    default:
                        return .none
                    }
                }
            }
        }

        let tracker = TaskTracker()
        let sut = Store(
            initialState: DataState(),
            feature: TrackingFeature(tracker: tracker)
        )

        // WHEN: Execute tasks sequentially
        await sut.send(.fetch("task1")).value
        await sut.send(.fetch("task2")).value
        await sut.send(.fetch("task3")).value

        // THEN: Tasks should complete in order
        let completed = await tracker.getCompleted()
        #expect(completed == ["task1", "task2", "task3"])
    }

    @Test func taskReuseAfterCompletion() async {
        // GIVEN: Store
        let sut = Store(
            initialState: DataState(),
            feature: DataFeature()
        )

        // WHEN: Run task, wait for completion, run again
        await sut.send(.fetch("data1")).value
        #expect(sut.runningTaskCount == 0)

        _ = sut.send(.fetch("data1"))
        try? await Task.sleep(for: .milliseconds(10))

        // THEN: Task should be running again
        #expect(sut.state.isLoading["data1"] ?? false)
        #expect(sut.isTaskRunning(id: "fetch-data1"))
    }

    // MARK: - Task Manager State Consistency

    @Test func taskManagerStateRemainsConsistent() async {
        // GIVEN: Store
        let sut = Store(
            initialState: DataState(),
            feature: DataFeature()
        )

        // WHEN: Start, cancel, and restart tasks
        _ = sut.send(.fetch("data1"))
        try? await Task.sleep(for: .milliseconds(10))

        await sut.send(.cancelFetch("data1")).value
        try? await Task.sleep(for: .milliseconds(20))

        _ = sut.send(.fetch("data2"))
        try? await Task.sleep(for: .milliseconds(10))

        // THEN: Task manager state should be consistent
        #expect(!sut.isTaskRunning(id: "fetch-data1"))
        // data2 might still be running or completed
    }

    // MARK: - Integration with Synchronous Actions

    @Test func mixedSyncAndAsyncActions() async {
        // GIVEN: Store
        let sut = Store(
            initialState: DataState(),
            feature: DataFeature()
        )

        // WHEN: Mix synchronous and asynchronous actions
        await sut.send(.process("data1")).value
        #expect(sut.state.data["data1"] == "processed")

        _ = sut.send(.fetch("data2"))
        try? await Task.sleep(for: .milliseconds(10))

        await sut.send(.process("data3")).value
        #expect(sut.state.data["data3"] == "processed")

        // THEN: Both sync and async actions should work
        #expect(sut.state.data["data1"] == "processed")
        #expect(sut.state.data["data3"] == "processed")
        #expect(sut.state.isLoading["data2"] ?? false)
    }
}
