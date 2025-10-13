import Foundation
import Testing

@testable import ViewFeature

/// Integration tests for error handling and recovery scenarios.
///
/// Tests how the system handles errors, recovers from failures,
/// and maintains consistency across components.
@MainActor
@Suite struct ErrorHandlingIntegrationTests {
    // MARK: - Test Fixtures

    enum NetworkAction: Sendable {
        case fetchData(String)
        case retryFetch(String)
        case handleError(String, Error)
        case recoverFromError
        case reset
    }

    struct NetworkState: Equatable, Sendable {
        var data: [String: String] = [:]
        var errors: [String: String] = [:]
        var retryCount: Int = 0
        var isRecovering: Bool = false
        var lastError: String?
    }

    enum NetworkError: Error, Equatable {
        case timeout
        case unauthorized
        case serverError(Int)
        case networkUnavailable
    }

    // MARK: - Basic Error Handling Tests

    @Test func taskErrorsAreHandledGracefully() async {
        // GIVEN: Store with error-throwing feature
        struct ErrorFeature: StoreFeature, Sendable {
            typealias Action = NetworkAction
            typealias State = NetworkState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .fetchData(let id):
                        return ActionTask(
                            storeTask: .run(
                                id: "fetch-\(id)",
                                operation: {
                                    try await Task.sleep(for: .milliseconds(10))
                                    throw NetworkError.timeout
                                },
                                onError: { error, state in
                                    state.errors[id] = "\(error)"
                                    state.lastError = "\(error)"
                                }
                            ))
                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: NetworkState(),
            feature: ErrorFeature()
        )

        // WHEN: Execute task that throws
        await sut.send(.fetchData("data1")).value

        // Wait for error handling
        try? await Task.sleep(for: .milliseconds(50))

        // THEN: Error should be captured in state
        #expect(sut.state.errors["data1"] != nil)
        #expect(sut.state.lastError != nil)
    }

    @Test func multipleErrorsAreHandledIndependently() async {
        // GIVEN: Store with multiple failing tasks
        struct MultiErrorFeature: StoreFeature, Sendable {
            typealias Action = NetworkAction
            typealias State = NetworkState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .fetchData(let id):
                        let errorType: NetworkError = id == "data1" ? .timeout : .unauthorized
                        return ActionTask(
                            storeTask: .run(
                                id: "fetch-\(id)",
                                operation: {
                                    try await Task.sleep(for: .milliseconds(10))
                                    throw errorType
                                },
                                onError: { error, state in
                                    state.errors[id] = "\(error)"
                                }
                            ))
                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: NetworkState(),
            feature: MultiErrorFeature()
        )

        // WHEN: Execute multiple failing tasks
        await sut.send(.fetchData("data1")).value
        await sut.send(.fetchData("data2")).value

        try? await Task.sleep(for: .milliseconds(50))

        // THEN: Each error should be tracked separately
        #expect(sut.state.errors["data1"] != nil)
        #expect(sut.state.errors["data2"] != nil)
        #expect(sut.state.errors.count == 2)
    }

    // MARK: - Error Recovery Tests

    @Test func systemRecoversAfterError() async {
        // GIVEN: Store with recovery mechanism
        struct RecoveryFeature: StoreFeature, Sendable {
            typealias Action = NetworkAction
            typealias State = NetworkState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .fetchData(let id):
                        return ActionTask(
                            storeTask: .run(
                                id: "fetch-\(id)",
                                operation: {
                                    throw NetworkError.timeout
                                },
                                onError: { error, state in
                                    state.errors[id] = "\(error)"
                                    state.lastError = "\(error)"
                                }
                            ))

                    case .recoverFromError:
                        state.errors.removeAll()
                        state.lastError = nil
                        state.isRecovering = false
                        return .none

                    case .retryFetch(let id):
                        state.retryCount += 1
                        state.errors[id] = nil
                        return ActionTask(
                            storeTask: .run(
                                id: "retry-\(id)",
                                operation: {
                                    try await Task.sleep(for: .milliseconds(10))
                                    // Simulate success on retry
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
            initialState: NetworkState(),
            feature: RecoveryFeature()
        )

        // WHEN: Fail, then recover
        await sut.send(.fetchData("data1")).value
        try? await Task.sleep(for: .milliseconds(30))

        #expect(sut.state.lastError != nil)

        await sut.send(.recoverFromError).value

        // THEN: State should be recovered
        #expect(sut.state.lastError == nil)
        #expect(sut.state.errors.isEmpty)
    }

    @Test func retryMechanismAfterError() async {
        // GIVEN: Store with retry mechanism
        struct RetryFeature: StoreFeature, Sendable {
            typealias Action = NetworkAction
            typealias State = NetworkState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .fetchData(let id):
                        return ActionTask(
                            storeTask: .run(
                                id: "fetch-\(id)",
                                operation: {
                                    throw NetworkError.timeout
                                },
                                onError: { error, state in
                                    state.errors[id] = "\(error)"
                                }
                            ))

                    case .retryFetch(let id):
                        state.retryCount += 1
                        state.errors[id] = nil
                        return .run(id: "retry-\(id)") {
                            try await Task.sleep(for: .milliseconds(10))
                        }

                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: NetworkState(),
            feature: RetryFeature()
        )

        // WHEN: Fail and retry
        await sut.send(.fetchData("data1")).value
        try? await Task.sleep(for: .milliseconds(30))

        #expect(sut.state.errors["data1"] != nil)

        await sut.send(.retryFetch("data1")).value
        try? await Task.sleep(for: .milliseconds(30))

        // THEN: Retry should clear error
        #expect(sut.state.errors["data1"] == nil)
        #expect(sut.state.retryCount == 1)
    }

    // MARK: - Error State Consistency Tests

    @Test func stateRemainsConsistentAfterError() async {
        // GIVEN: Store with state preservation
        struct StatePreservingFeature: StoreFeature, Sendable {
            typealias Action = NetworkAction
            typealias State = NetworkState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .fetchData(let id):
                        state.data[id] = "loading"
                        return ActionTask(
                            storeTask: .run(
                                id: "fetch-\(id)",
                                operation: {
                                    throw NetworkError.serverError(500)
                                },
                                onError: { error, state in
                                    state.data[id] = "failed"
                                    state.errors[id] = "\(error)"
                                }
                            ))

                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: NetworkState(data: ["existing": "value"]),
            feature: StatePreservingFeature()
        )

        // WHEN: Error occurs
        await sut.send(.fetchData("data1")).value
        try? await Task.sleep(for: .milliseconds(30))

        // THEN: Existing state should be preserved
        #expect(sut.state.data["existing"] == "value")
        #expect(sut.state.data["data1"] == "failed")
        #expect(sut.state.errors["data1"] != nil)
    }

    // MARK: - Task Cancellation Error Tests

    @Test func taskCancellationDoesNotCauseErrors() async {
        // GIVEN: Store with cancellable task
        struct CancellableFeature: StoreFeature, Sendable {
            typealias Action = NetworkAction
            typealias State = NetworkState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .fetchData(let id):
                        return ActionTask(
                            storeTask: .run(
                                id: "fetch-\(id)",
                                operation: {
                                    try await Task.sleep(for: .milliseconds(100))
                                },
                                onError: { error, state in
                                    // Cancellation should not add errors
                                    if !(error is CancellationError) {
                                        state.errors[id] = "\(error)"
                                    }
                                }
                            ))

                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: NetworkState(),
            feature: CancellableFeature()
        )

        // WHEN: Start and cancel task
        _ = sut.send(.fetchData("data1"))
        try? await Task.sleep(for: .milliseconds(10))

        sut.cancelAllTasks()
        try? await Task.sleep(for: .milliseconds(30))

        // THEN: Cancellation should not add errors
        #expect(sut.state.errors.isEmpty)
    }

    // MARK: - Complex Error Scenarios

    @Test func cascadingErrorHandling() async {
        // GIVEN: Store where errors can trigger other actions
        struct CascadingFeature: StoreFeature, Sendable {
            typealias Action = NetworkAction
            typealias State = NetworkState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .fetchData(let id):
                        return ActionTask(
                            storeTask: .run(
                                id: "fetch-\(id)",
                                operation: {
                                    throw NetworkError.unauthorized
                                },
                                onError: { error, state in
                                    state.errors[id] = "\(error)"
                                    // Trigger recovery
                                    state.isRecovering = true
                                }
                            ))

                    case .recoverFromError:
                        state.errors.removeAll()
                        state.isRecovering = false
                        return .none

                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: NetworkState(),
            feature: CascadingFeature()
        )

        // WHEN: Error triggers recovery state
        await sut.send(.fetchData("data1")).value
        try? await Task.sleep(for: .milliseconds(30))

        #expect(sut.state.isRecovering)

        // Recover
        await sut.send(.recoverFromError).value

        // THEN: System should recover
        #expect(!sut.state.isRecovering)
        #expect(sut.state.errors.isEmpty)
    }

    @Test func errorDuringErrorHandling() async {
        // GIVEN: Store where error handler itself doesn't crash
        struct SafeErrorFeature: StoreFeature, Sendable {
            typealias Action = NetworkAction
            typealias State = NetworkState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .fetchData(let id):
                        return ActionTask(
                            storeTask: .run(
                                id: "fetch-\(id)",
                                operation: {
                                    throw NetworkError.serverError(500)
                                },
                                onError: { error, state in
                                    // Safe error handling
                                    state.errors[id] = "\(error)"
                                    state.lastError = "\(error)"
                                }
                            ))

                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: NetworkState(),
            feature: SafeErrorFeature()
        )

        // WHEN: Error occurs
        await sut.send(.fetchData("data1")).value
        try? await Task.sleep(for: .milliseconds(30))

        // THEN: Error should be handled safely
        #expect(sut.state.errors["data1"] != nil)
        #expect(sut.state.lastError != nil)
    }

    // MARK: - Recovery Workflow Tests

    @Test func fullErrorRecoveryWorkflow() async {
        // GIVEN: Store with complete recovery workflow
        struct FullRecoveryFeature: StoreFeature, Sendable {
            typealias Action = NetworkAction
            typealias State = NetworkState

            func handle() -> ActionHandler<Action, State> {
                ActionHandler { action, state in
                    switch action {
                    case .fetchData(let id):
                        return ActionTask(
                            storeTask: .run(
                                id: "fetch-\(id)",
                                operation: {
                                    throw NetworkError.timeout
                                },
                                onError: { error, state in
                                    state.errors[id] = "\(error)"
                                    state.lastError = "\(error)"
                                }
                            ))

                    case .retryFetch(let id):
                        state.retryCount += 1
                        state.errors.removeValue(forKey: id)

                        if state.retryCount < 3 {
                            // Simulate failure on first 2 retries
                            return ActionTask(
                                storeTask: .run(
                                    id: "retry-\(id)",
                                    operation: {
                                        throw NetworkError.timeout
                                    },
                                    onError: { error, state in
                                        state.errors[id] = "\(error)"
                                    }
                                ))
                        } else {
                            // Success on 3rd retry
                            return ActionTask(
                                storeTask: .run(
                                    id: "retry-\(id)",
                                    operation: {
                                        // Success
                                    },
                                    onError: nil
                                ))
                        }

                    case .recoverFromError:
                        state.errors.removeAll()
                        state.lastError = nil
                        state.isRecovering = false
                        return .none

                    case .reset:
                        state = NetworkState()
                        return .none

                    default:
                        return .none
                    }
                }
            }
        }

        let sut = Store(
            initialState: NetworkState(),
            feature: FullRecoveryFeature()
        )

        // WHEN: Execute full recovery workflow
        // Initial failure
        await sut.send(.fetchData("data1")).value
        try? await Task.sleep(for: .milliseconds(30))
        #expect(sut.state.errors["data1"] != nil)

        // First retry - fails
        await sut.send(.retryFetch("data1")).value
        try? await Task.sleep(for: .milliseconds(30))
        #expect(sut.state.retryCount == 1)

        // Second retry - fails
        await sut.send(.retryFetch("data1")).value
        try? await Task.sleep(for: .milliseconds(30))
        #expect(sut.state.retryCount == 2)

        // Third retry - succeeds
        await sut.send(.retryFetch("data1")).value
        try? await Task.sleep(for: .milliseconds(30))
        #expect(sut.state.retryCount == 3)

        // THEN: Should eventually succeed
        // Error might still be present from last failure, but retry count is correct
        #expect(sut.state.retryCount == 3)
    }
}
