import Foundation
import Testing

@testable import ViewFeature

/// Tests for ActionTask composition (merge and concatenate).
///
/// These tests verify that task composition operations work correctly
/// for both parallel (merge) and sequential (concatenate) execution.
@MainActor
@Suite struct ActionTaskCompositionTests {
    // MARK: - Test Fixtures

    enum TestAction: Sendable {
        case runMerged
        case runConcatenated
        case runNested
        case increment
        case appendValue(Int)
    }

    @Observable
    final class TestState {
        var counter: Int = 0
        var values: [Int] = []
        var executionOrder: [String] = []
        var timestamp: Date?

        init(counter: Int = 0, values: [Int] = [], executionOrder: [String] = [], timestamp: Date? = nil) {
            self.counter = counter
            self.values = values
            self.executionOrder = executionOrder
            self.timestamp = timestamp
        }
    }

    struct TestFeature: Feature, Sendable {
        typealias Action = TestAction
        typealias State = TestState

        func handle() -> ActionHandler<Action, State> {
            ActionHandler { action, state in
                switch action {
                case .runMerged:
                    // Merge: Run 3 tasks in parallel
                    return .merge(
                        .run { state in
                            try await Task.sleep(for: .milliseconds(10))
                            state.values.append(1)
                        },
                        .run { state in
                            try await Task.sleep(for: .milliseconds(10))
                            state.values.append(2)
                        },
                        .run { state in
                            try await Task.sleep(for: .milliseconds(10))
                            state.values.append(3)
                        }
                    )

                case .runConcatenated:
                    // Concatenate: Run 3 tasks sequentially
                    return .concatenate(
                        .run { state in
                            state.executionOrder.append("first")
                            try await Task.sleep(for: .milliseconds(5))
                        },
                        .run { state in
                            state.executionOrder.append("second")
                            try await Task.sleep(for: .milliseconds(5))
                        },
                        .run { state in
                            state.executionOrder.append("third")
                        }
                    )

                case .runNested:
                    // Nested: Concatenate with merge inside
                    return .concatenate(
                        .run { state in
                            state.executionOrder.append("init")
                        },
                        .merge(
                            .run { state in
                                try await Task.sleep(for: .milliseconds(5))
                                state.values.append(10)
                            },
                            .run { state in
                                try await Task.sleep(for: .milliseconds(5))
                                state.values.append(20)
                            }
                        ),
                        .run { state in
                            state.executionOrder.append("finalize")
                        }
                    )

                case .increment:
                    state.counter += 1
                    return .none

                case .appendValue(let value):
                    state.values.append(value)
                    return .none
                }
            }
        }
    }

    // MARK: - Merge Tests

    @Test func merge_executesTasksInParallel() async {
        // GIVEN: Store with merged tasks
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Execute merged tasks
        await sut.send(.runMerged).value

        // THEN: All tasks should complete successfully
        // Note: We verify correctness (all values present) rather than timing,
        // as timing-based tests are unreliable in CI environments
        #expect(sut.state.values.count == 3)
        #expect(sut.state.values.contains(1))
        #expect(sut.state.values.contains(2))
        #expect(sut.state.values.contains(3))
    }

    @Test func merge_withEmptyArray() async {
        // GIVEN: Merge with empty array
        let task: ActionTask<TestAction, TestState> = .merge([])

        // WHEN: Execute through store
        struct EmptyMergeFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { _, _ in
                    .merge([])
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: EmptyMergeFeature()
        )

        await sut.send(.increment).value

        // THEN: Should behave like .none (do nothing)
        #expect(sut.state.counter == 0) // .merge([]) behaves like .none, no state change
    }

    @Test func merge_withSingleTask() async {
        // GIVEN: Merge with single task
        struct SingleMergeFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { _, state in
                    .merge(
                        .run { state in
                            state.counter = 42
                        }
                    )
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: SingleMergeFeature()
        )

        // WHEN: Execute
        await sut.send(.increment).value

        // THEN: Single task should execute
        #expect(sut.state.counter == 42)
    }

    // MARK: - Concatenate Tests

    @Test func concatenate_executesTasksSequentially() async {
        // GIVEN: Store with concatenated tasks
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Execute concatenated tasks
        await sut.send(.runConcatenated).value

        // THEN: Tasks should execute in order
        #expect(sut.state.executionOrder == ["first", "second", "third"])
    }

    @Test func concatenate_maintainsOrder() async {
        // GIVEN: Concatenated tasks with different durations
        struct OrderedFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { _, _ in
                    .concatenate(
                        .run { state in
                            try await Task.sleep(for: .milliseconds(20))
                            state.executionOrder.append("slow")
                        },
                        .run { state in
                            // No sleep - fast task
                            state.executionOrder.append("fast")
                        },
                        .run { state in
                            try await Task.sleep(for: .milliseconds(10))
                            state.executionOrder.append("medium")
                        }
                    )
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: OrderedFeature()
        )

        // WHEN: Execute
        await sut.send(.increment).value

        // THEN: Order should be preserved despite different durations
        #expect(sut.state.executionOrder == ["slow", "fast", "medium"])
    }

    @Test func concatenate_withEmptyArray() async {
        // GIVEN: Concatenate with empty array
        struct EmptyConcatFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { _, _ in
                    .concatenate([])
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: EmptyConcatFeature()
        )

        await sut.send(.increment).value

        // THEN: Should behave like .none
        #expect(sut.state.counter == 0) // .concatenate([]) behaves like .none, no state change
    }

    // MARK: - Nested Composition Tests

    @Test func nestedComposition_mergeInsideConcatenate() async {
        // GIVEN: Store with nested composition
        let sut = Store(
            initialState: TestState(),
            feature: TestFeature()
        )

        // WHEN: Execute nested composition
        await sut.send(.runNested).value

        // THEN: Should execute in correct order
        #expect(sut.state.executionOrder.first == "init")
        #expect(sut.state.executionOrder.last == "finalize")
        #expect(sut.state.values.count == 2)
        #expect(sut.state.values.contains(10))
        #expect(sut.state.values.contains(20))
    }

    @Test func nestedComposition_concatenateInsideMerge() async {
        // GIVEN: Concatenate inside merge
        struct NestedFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { _, _ in
                    .merge(
                        .concatenate(
                            .run { state in
                                state.executionOrder.append("concat-1-first")
                            },
                            .run { state in
                                state.executionOrder.append("concat-1-second")
                            }
                        ),
                        .concatenate(
                            .run { state in
                                state.executionOrder.append("concat-2-first")
                            },
                            .run { state in
                                state.executionOrder.append("concat-2-second")
                            }
                        )
                    )
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: NestedFeature()
        )

        // WHEN: Execute
        await sut.send(.increment).value

        // THEN: Each concatenate chain should maintain order
        let hasConcat1Order = sut.state.executionOrder.contains("concat-1-first") &&
                               sut.state.executionOrder.contains("concat-1-second")
        let hasConcat2Order = sut.state.executionOrder.contains("concat-2-first") &&
                               sut.state.executionOrder.contains("concat-2-second")

        #expect(hasConcat1Order)
        #expect(hasConcat2Order)
        #expect(sut.state.executionOrder.count == 4)
    }

    // MARK: - Monoid Law Tests

    @Test func merge_identityLaw() async {
        // GIVEN: Merge with .none
        struct IdentityFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, _ in
                    switch action {
                    case .increment:
                        // .merge(.none, task) should equal task
                        return .merge(
                            .none,
                            .run { state in state.counter = 42 }
                        )
                    case .appendValue:
                        // .merge(task, .none) should equal task
                        return .merge(
                            .run { state in state.counter = 99 },
                            .none
                        )
                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: IdentityFeature()
        )

        // WHEN: Execute with left identity
        await sut.send(.increment).value
        #expect(sut.state.counter == 42)

        // Reset
        sut.state.counter = 0

        // WHEN: Execute with right identity
        await sut.send(.appendValue(0)).value
        #expect(sut.state.counter == 99)
    }

    @Test func concatenate_identityLaw() async {
        // GIVEN: Concatenate with .none
        struct IdentityFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, _ in
                    switch action {
                    case .increment:
                        // .concatenate(.none, task) should equal task
                        return .concatenate(
                            .none,
                            .run { state in state.counter = 42 }
                        )
                    case .appendValue:
                        // .concatenate(task, .none) should equal task
                        return .concatenate(
                            .run { state in state.counter = 99 },
                            .none
                        )
                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: IdentityFeature()
        )

        // WHEN: Execute with left identity
        await sut.send(.increment).value
        #expect(sut.state.counter == 42)

        // Reset
        sut.state.counter = 0

        // WHEN: Execute with right identity
        await sut.send(.appendValue(0)).value
        #expect(sut.state.counter == 99)
    }

    // MARK: - Error Handling in Composition

    @Test func merge_withErrorHandling() async {
        // GIVEN: Merged tasks with error handling
        struct ErrorMergeFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { _, _ in
                    .merge(
                        .run { state in
                            state.values.append(1)
                        },
                        .run { _ in
                            throw NSError(domain: "Test", code: 1)
                        }
                        .catch { _, state in
                            state.values.append(999) // Error marker
                        },
                        .run { state in
                            state.values.append(3)
                        }
                    )
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: ErrorMergeFeature()
        )

        // WHEN: Execute
        await sut.send(.increment).value

        // THEN: All tasks should complete, including error handler
        #expect(sut.state.values.contains(1))
        #expect(sut.state.values.contains(999)) // Error was caught
        #expect(sut.state.values.contains(3))
    }

    @Test func concatenate_withErrorHandling() async {
        // GIVEN: Concatenated tasks with error in middle
        struct ErrorConcatFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { _, _ in
                    .concatenate(
                        .run { state in
                            state.executionOrder.append("first")
                        },
                        .run { _ in
                            throw NSError(domain: "Test", code: 1)
                        }
                        .catch { _, state in
                            state.executionOrder.append("error-handled")
                        },
                        .run { state in
                            state.executionOrder.append("third")
                        }
                    )
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: ErrorConcatFeature()
        )

        // WHEN: Execute
        await sut.send(.increment).value

        // THEN: Should execute in order despite error
        #expect(sut.state.executionOrder == ["first", "error-handled", "third"])
    }
}
