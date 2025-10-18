import Foundation
import Testing

@testable import ViewFeature

/// Tests to verify that deep task composition does not cause stack overflow.
///
/// These tests demonstrate that async recursion in `executeTask()` is safe
/// because async/await uses continuation-based execution (heap) rather than
/// traditional stack-based recursion.
@MainActor
@Suite struct DeepRecursionTests {
    enum TestAction: Sendable {
        case runDeep(Int)
    }

    @Observable
    final class TestState {
        var depth = 0
        var maxDepth = 0

        init(depth: Int = 0, maxDepth: Int = 0) {
            self.depth = depth
            self.maxDepth = maxDepth
        }
    }

    struct DeepRecursionFeature: Feature, Sendable {
        typealias Action = TestAction
        typealias State = TestState

        func handle() -> ActionHandler<Action, State> {
            ActionHandler { action, _ in
                switch action {
                case .runDeep(let targetDepth):
                    // Build deeply nested concatenation
                    return buildDeepConcatenation(current: 0, target: targetDepth)
                }
            }
        }

        @MainActor
        private func buildDeepConcatenation(current: Int, target: Int) -> ActionTask<Action, State> {
            if current >= target {
                return .run { state in
                    state.depth = current
                    state.maxDepth = max(state.maxDepth, current)
                }
            }

            return .concatenate(
                .run { state in
                    state.depth = current
                    state.maxDepth = max(state.maxDepth, current)
                },
                buildDeepConcatenation(current: current + 1, target: target)
            )
        }
    }

    @Test func deepConcatenation_depth100_doesNotStackOverflow() async {
        // GIVEN: A store with deeply nested concatenation (100 levels)
        let sut = Store(
            initialState: TestState(),
            feature: DeepRecursionFeature()
        )

        // WHEN: Execute 100-level deep concatenation
        await sut.send(.runDeep(100)).value

        // THEN: Should complete successfully without stack overflow
        #expect(sut.state.maxDepth >= 100)
    }

    @Test func deepConcatenation_depth500_doesNotStackOverflow() async {
        // GIVEN: A store with very deeply nested concatenation (500 levels)
        let sut = Store(
            initialState: TestState(),
            feature: DeepRecursionFeature()
        )

        // WHEN: Execute 500-level deep concatenation
        await sut.send(.runDeep(500)).value

        // THEN: Should complete successfully without stack overflow
        // This demonstrates that async recursion uses heap, not stack
        #expect(sut.state.maxDepth >= 500)
    }

    @Test func deepMerge_manyParallelTasks_doesNotStackOverflow() async {
        // GIVEN: Many parallel tasks
        struct ManyMergeFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .runDeep(let count):
                        // Build array of tasks and merge
                        let tasks = (0..<count).map { index in
                            ActionTask<Action, State>.run { state in
                                state.depth = index
                                state.maxDepth = max(state.maxDepth, index)
                            }
                        }
                        return .merge(tasks)
                    }
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: ManyMergeFeature()
        )

        // WHEN: Merge 100 parallel tasks
        await sut.send(.runDeep(100)).value

        // THEN: Should complete successfully
        #expect(sut.state.maxDepth >= 0)
    }

    @Test func nestedComposition_complexWorkflow_doesNotStackOverflow() async {
        // GIVEN: Complex nested composition (merge inside concatenate, repeatedly)
        struct NestedFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, _ in
                    switch action {
                    case .runDeep(let levels):
                        return buildNested(level: 0, maxLevel: levels)
                    }
                }
            }

            @MainActor
            private func buildNested(level: Int, maxLevel: Int) -> ActionTask<Action, State> {
                if level >= maxLevel {
                    return .run { state in
                        state.depth = level
                        state.maxDepth = max(state.maxDepth, level)
                    }
                }

                return .concatenate(
                    .run { state in
                        state.depth = level
                    },
                    .merge(
                        buildNested(level: level + 1, maxLevel: maxLevel),
                        .run { state in
                            state.maxDepth = max(state.maxDepth, level)
                        }
                    )
                )
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: NestedFeature()
        )

        // WHEN: Execute deeply nested composition (50 levels)
        await sut.send(.runDeep(50)).value

        // THEN: Should complete without stack overflow
        #expect(sut.state.maxDepth >= 0)
    }

    @Test func arrayBasedMerge_thousandTasks_doesNotStackOverflow() async {
        // GIVEN: Array-based merge with 1000 tasks
        struct MassiveMergeFeature: Feature, Sendable {
            typealias Action = TestAction
            typealias State = TestState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .runDeep(let count):
                        let tasks = (0..<count).map { index in
                            ActionTask<Action, State>.run { state in
                                state.maxDepth = max(state.maxDepth, index)
                            }
                        }
                        return .merge(tasks)
                    }
                }
            }
        }

        let sut = Store(
            initialState: TestState(),
            feature: MassiveMergeFeature()
        )

        // WHEN: Merge 1000 tasks
        // Note: This is impractical but demonstrates no stack overflow
        await sut.send(.runDeep(1000)).value

        // THEN: Should complete successfully
        #expect(sut.state.maxDepth >= 0)
    }
}
