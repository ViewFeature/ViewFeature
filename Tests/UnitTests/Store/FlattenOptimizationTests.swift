import Foundation
import Testing

@testable import ViewFeature

/// Tests verifying flatten optimization works correctly
@MainActor
@Suite struct FlattenOptimizationTests {
    enum TestAction: Sendable {
        case test
    }

    @Observable
    final class TestState {
        var counter = 0
        init() {}
    }

    struct TestFeature: Feature, Sendable {
        typealias Action = TestAction
        typealias State = TestState

        func handle() -> ActionHandler<Action, State> {
            ActionHandler { _, _ in .none }
        }
    }

    // MARK: - Flatten Tests

    @Test func flattenMerged_withSimpleMerge() {
        // GIVEN: Simple merge of 3 tasks
        let task: ActionTask<TestAction, TestState> = .merge(
            .run { _ in },
            .run { _ in },
            .run { _ in }
        )

        // WHEN: Flatten
        let flattened = task.flattenMerged()

        // THEN: Should have 3 tasks
        #expect(flattened.count == 3)
    }

    @Test func flattenMerged_withNestedMerge() {
        // GIVEN: Nested merge structure
        let task: ActionTask<TestAction, TestState> = .merge(
            .merge(
                .run { _ in },
                .run { _ in }
            ),
            .merge(
                .run { _ in },
                .run { _ in }
            )
        )

        // WHEN: Flatten
        let flattened = task.flattenMerged()

        // THEN: Should have 4 tasks (all flattened)
        #expect(flattened.count == 4)
    }

    @Test func flattenMerged_withLargeArray() {
        // GIVEN: Large array of tasks
        let tasks = (0..<100).map { _ in
            ActionTask<TestAction, TestState>.run { _ in }
        }
        let merged = ActionTask<TestAction, TestState>.merge(tasks)

        // WHEN: Flatten
        let flattened = merged.flattenMerged()

        // THEN: Should have 100 individual tasks
        #expect(flattened.count == 100)
    }

    @Test func flattenMerged_withNoneTask() {
        // GIVEN: Merge with .none
        let task: ActionTask<TestAction, TestState> = .merge(
            .run { _ in },
            .none,
            .run { _ in }
        )

        // WHEN: Flatten
        let flattened = task.flattenMerged()

        // THEN: .none is identity, so effective tasks are 2
        // merge(.run, .none, .run) -> merge(.run, .run) due to identity law
        #expect(flattened.count == 2)
    }

    @Test func flattenMerged_withMixedTaskTypes() {
        // GIVEN: Merge with different task types
        let task: ActionTask<TestAction, TestState> = .merge(
            .run { _ in },
            .cancel(id: "test"),
            .concatenate(
                .run { _ in },
                .run { _ in }
            )
        )

        // WHEN: Flatten
        let flattened = task.flattenMerged()

        // THEN: Should have 3 leaf tasks (concatenate stays as one)
        #expect(flattened.count == 3)
    }

    @Test func flattenConcatenated_withSimpleConcatenation() {
        // GIVEN: Simple concatenation of 3 tasks
        let task: ActionTask<TestAction, TestState> = .concatenate(
            .run { _ in },
            .run { _ in },
            .run { _ in }
        )

        // WHEN: Flatten
        let flattened = task.flattenConcatenated()

        // THEN: Should have 3 tasks
        #expect(flattened.count == 3)
    }

    @Test func flattenConcatenated_withNestedConcatenation() {
        // GIVEN: Nested concatenation structure
        let task: ActionTask<TestAction, TestState> = .concatenate(
            .concatenate(
                .run { _ in },
                .run { _ in }
            ),
            .concatenate(
                .run { _ in },
                .run { _ in }
            )
        )

        // WHEN: Flatten
        let flattened = task.flattenConcatenated()

        // THEN: Should have 4 tasks (all flattened)
        #expect(flattened.count == 4)
    }

    @Test func flattenConcatenated_withLargeArray() {
        // GIVEN: Large array of tasks
        let tasks = (0..<100).map { _ in
            ActionTask<TestAction, TestState>.run { _ in }
        }
        let concatenated = ActionTask<TestAction, TestState>.concatenate(tasks)

        // WHEN: Flatten
        let flattened = concatenated.flattenConcatenated()

        // THEN: Should have 100 individual tasks
        #expect(flattened.count == 100)
    }

    @Test func flattenConcatenated_withMixedTaskTypes() {
        // GIVEN: Concatenate with different task types
        let task: ActionTask<TestAction, TestState> = .concatenate(
            .run { _ in },
            .cancel(id: "test"),
            .merge(
                .run { _ in },
                .run { _ in }
            )
        )

        // WHEN: Flatten
        let flattened = task.flattenConcatenated()

        // THEN: Should have 3 leaf tasks (merge stays as one)
        #expect(flattened.count == 3)
    }

    // MARK: - Integration Tests

    @Test func optimizedExecution_behavesIdentically() async {
        // GIVEN: Store with complex merge
        struct ComplexFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { _, _ in
                    .merge(
                        .run { state in state.counter += 1 },
                        .run { state in state.counter += 10 },
                        .run { state in state.counter += 100 }
                    )
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: ComplexFeature()
        )

        // WHEN: Execute
        await sut.send(.test).value

        // THEN: All tasks should have executed
        #expect(sut.state.counter == 111)
    }

    @Test func optimizedExecution_maintainsOrder() async {
        // GIVEN: Store with concatenation
        struct OrderFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { _, _ in
                    .concatenate(
                        .run { state in state.counter = 1 },
                        .run { state in state.counter *= 10 },
                        .run { state in state.counter += 5 }
                    )
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: OrderFeature()
        )

        // WHEN: Execute
        await sut.send(.test).value

        // THEN: Execution order should be maintained (1 -> 10 -> 15)
        #expect(sut.state.counter == 15)
    }
}
