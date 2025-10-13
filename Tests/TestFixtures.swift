import XCTest

@testable import ViewFeature

// MARK: - Shared Test Fixtures for DRY Test Code

/// Common test fixtures to eliminate duplication across test files
/// Following DRY principle by centralizing repeated State/Action/Feature patterns

// MARK: - Counter Test Fixtures

public struct CounterState: Equatable, Sendable {
    public var count: Int

    public init(count: Int = 0) {
        self.count = count
    }
}

public enum CounterAction: Sendable {
    case increment
    case decrement
    case reset
    case set(Int)
}

public struct CounterFeature: StoreFeature {
    public init() {}

    public func handle() -> ActionHandler<CounterAction, CounterState> {
        ActionHandler { action, state in
            switch action {
            case .increment:
                state.count += 1
                return .none
            case .decrement:
                state.count -= 1
                return .none
            case .reset:
                state.count = 0
                return .none
            case .set(let value):
                state.count = value
                return .none
            }
        }
    }
}

// MARK: - Generic Test Fixtures

public struct TestState: Equatable, Sendable {
    public var value: Int
    public var lastTaskId: String?
    public var isLoading: Bool
    public var errorMessage: String?

    public init(
        value: Int = 0,
        lastTaskId: String? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) {
        self.value = value
        self.lastTaskId = lastTaskId
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }
}

public enum TestAction: Sendable {
    case increment
    case decrement
    case setTaskId(String)
    case setLoading(Bool)
    case setError(String?)
    case reset
}

public struct TestFeature: StoreFeature {
    public init() {}

    public func handle() -> ActionHandler<TestAction, TestState> {
        ActionHandler { action, state in
            switch action {
            case .increment:
                state.value += 1
                return .none
            case .decrement:
                state.value -= 1
                return .none
            case .setTaskId(let id):
                state.lastTaskId = id
                return .none
            case .setLoading(let loading):
                state.isLoading = loading
                return .none
            case .setError(let error):
                state.errorMessage = error
                return .none
            case .reset:
                state = TestState()
                return .none
            }
        }
    }
}

// MARK: - Concurrent Test Fixtures

public struct ConcurrentState: Equatable, Sendable {
    public var operations: [String]
    public var completedCount: Int

    public init(operations: [String] = [], completedCount: Int = 0) {
        self.operations = operations
        self.completedCount = completedCount
    }
}

public enum ConcurrentAction: Sendable {
    case addOperation(String)
    case completeOperation
    case reset
}

public struct ConcurrentFeature: StoreFeature {
    public init() {}

    public func handle() -> ActionHandler<ConcurrentAction, ConcurrentState> {
        ActionHandler { action, state in
            switch action {
            case .addOperation(let operation):
                state.operations.append(operation)
                return .none
            case .completeOperation:
                state.completedCount += 1
                return .none
            case .reset:
                state = ConcurrentState()
                return .none
            }
        }
    }
}

// MARK: - Test Utilities

public enum TestFixtures {
    /// Create a basic counter store for testing
    @MainActor
    public static func createCounterStore(
        initialCount: Int = 0
    ) -> Store<CounterFeature> {
        Store(
            initialState: CounterState(count: initialCount),
            feature: CounterFeature()
        )
    }

    /// Create a test store for testing
    @MainActor
    public static func createTestStore(
        initialValue: Int = 0
    ) -> Store<TestFeature> {
        Store(
            initialState: TestState(value: initialValue),
            feature: TestFeature()
        )
    }

    /// Create a concurrent test store
    @MainActor
    public static func createConcurrentStore() -> Store<ConcurrentFeature> {
        Store(
            initialState: ConcurrentState(),
            feature: ConcurrentFeature()
        )
    }
}

// MARK: - Test Assertions Extensions

extension XCTestCase {
    /// Wait for async condition with timeout
    public func waitFor(
        _ condition: @escaping () async -> Bool,
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let start = Date()
        while await !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Condition not met within timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
    }

    /// Assert state equals expected with better error messages
    public func assertState<State: Equatable>(
        _ state: State,
        equals expected: State,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(state, expected, "State does not match expected value", file: file, line: line)
    }
}
