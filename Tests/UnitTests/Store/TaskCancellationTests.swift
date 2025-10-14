import Foundation
import Testing

@testable import ViewFeature

/// Tests to verify task cancellation works correctly
@MainActor
@Suite struct TaskCancellationTests {
    // MARK: - Test Fixtures

    @Observable
    final class TestState {
        var count: Int = 0
        var isLoading: Bool = false
        var completed: Bool = false

        init(count: Int = 0, isLoading: Bool = false, completed: Bool = false) {
            self.count = count
            self.isLoading = isLoading
            self.completed = completed
        }
    }

    enum TestAction: Sendable {
        case startTask
        case cancelTask
        case taskCompleted
    }

    struct TestFeature: Feature, Sendable {
        typealias Action = TestAction
        typealias State = TestState

        func handle() -> ActionHandler<Action, State> {
            ActionHandler { action, state in
                switch action {
                case .startTask:
                    state.isLoading = true
                    return .run(id: "test-task") { state in
                        try await Task.sleep(for: .milliseconds(100))
                        // Check if task was cancelled during sleep
                        try Task.checkCancellation()
                        // This should NOT execute if cancelled
                        state.count += 1
                        state.completed = true
                        state.isLoading = false
                    }
                    .catch { _, state in
                        state.isLoading = false
                    }

                case .cancelTask:
                    state.isLoading = false
                    return .cancel(id: "test-task")

                case .taskCompleted:
                    state.completed = true
                    return .none
                }
            }
        }
    }

    // MARK: - Tests

    @Test func taskCancellationPreventsStateChange() async {
        // GIVEN: Store with a long-running task
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Start task (fire-and-forget for concurrent execution)
        _ = sut.send(.startTask)

        // Give task time to start
        try? await Task.sleep(for: .milliseconds(10))

        // Verify task started
        #expect(sut.state.isLoading)
        #expect(sut.isTaskRunning(id: "test-task"))

        // Cancel the task before it completes
        await sut.send(.cancelTask).value

        // Wait for task to be cancelled
        try? await Task.sleep(for: .milliseconds(50))

        // THEN: State should NOT be changed by cancelled task
        // swiftlint:disable:next empty_count
        #expect(sut.state.count == 0) // Should NOT have been incremented
        #expect(sut.state.completed == false) // Should NOT have been set
        #expect(sut.state.isLoading == false) // Should be reset by cancel action
        #expect(!sut.isTaskRunning(id: "test-task"))
    }

    @Test func taskCompletesIfNotCancelled() async {
        // GIVEN: Store with a short task
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Start task and let it complete
        await sut.send(.startTask).value

        // Wait for task to complete
        try? await Task.sleep(for: .milliseconds(150))

        // THEN: State should be changed
        #expect(sut.state.count == 1)
        #expect(sut.state.completed == true)
        #expect(sut.state.isLoading == false)
        #expect(!sut.isTaskRunning(id: "test-task"))
    }

    @Test func multipleCancellations() async {
        // GIVEN: Store
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Start and cancel multiple tasks
        _ = sut.send(.startTask)
        try? await Task.sleep(for: .milliseconds(10))
        await sut.send(.cancelTask).value

        _ = sut.send(.startTask)
        try? await Task.sleep(for: .milliseconds(10))
        await sut.send(.cancelTask).value

        _ = sut.send(.startTask)
        try? await Task.sleep(for: .milliseconds(10))
        await sut.send(.cancelTask).value

        try? await Task.sleep(for: .milliseconds(50))

        // THEN: Count should still be 0 (all cancelled)
        // swiftlint:disable:next empty_count
        #expect(sut.state.count == 0)
        #expect(sut.state.completed == false)
    }

    @Test func cancelViaStoreAPI() async {
        // GIVEN: Store with running task
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Start task and cancel via Store.cancelTask
        _ = sut.send(.startTask)
        try? await Task.sleep(for: .milliseconds(10))

        // Cancel using Store's direct API instead of action
        sut.cancelTask(id: "test-task")

        try? await Task.sleep(for: .milliseconds(150))

        // THEN: Task should be cancelled
        // swiftlint:disable:next empty_count
        #expect(sut.state.count == 0)
        #expect(sut.state.completed == false)
        #expect(!sut.isTaskRunning(id: "test-task"))
    }
}
