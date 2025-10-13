# Testing Guide

Comprehensive testing strategies for ViewFeature applications.

## Overview

ViewFeature provides ``TestStore`` with three assertion patterns to accommodate different testing needs. Choose the pattern that best fits your state type and testing requirements.

## Testing Patterns

### Pattern 1: Full State Comparison

**Best for:** Equatable states with straightforward equality logic.

**Requirements:** State must conform to Equatable.

```swift
struct CounterFeature: StoreFeature {
    @Observable
    final class State: Equatable {
        var count = 0

        init(count: Int = 0) {
            self.count = count
        }

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.count == rhs.count
        }
    }

    enum Action: Sendable {
        case increment
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .increment:
                state.count += 1
                return .none
            }
        }
    }
}

@MainActor
final class CounterTests: XCTestCase {
    func testIncrement() async {
        let store = TestStore(
            initialState: CounterFeature.State(count: 0),
            feature: CounterFeature()
        )

        // Full state comparison validates entire state equality
        await store.send(.increment) { state in
            state.count = 1
        }
    }
}
```

**Benefits:**
- Catches unexpected state changes
- Clear error messages
- Most rigorous validation

**When to use:**
- Small, simple states
- All properties are Equatable
- Want maximum confidence

### Pattern 2: Custom Assertions

**Best for:** Non-Equatable states or complex validation logic.

**Requirements:** None - works with any state type.

```swift
struct AppFeature: StoreFeature {
    @Observable
    final class State {  // No Equatable conformance
        var user: User?
        var isLoading = false
        var metadata: [String: Any] = [:]
    }

    enum Action: Sendable {
        case loadUser
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .loadUser:
                state.isLoading = true
                state.user = User(name: "Alice")
                return .none
            }
        }
    }
}

@MainActor
final class AppTests: XCTestCase {
    func testLoadUser() async {
        let store = TestStore(
            initialState: AppFeature.State(),
            feature: AppFeature()
        )

        // Custom assertions - test only what matters
        await store.send(.loadUser, assert: { state in
            XCTAssertEqual(state.user?.name, "Alice")
            XCTAssertTrue(state.isLoading)
            // metadata not asserted - irrelevant to this test
        })
    }
}
```

**Benefits:**
- Works with any state type
- Test only relevant properties
- Flexible validation logic

**When to use:**
- Non-Equatable states (dictionaries, closures, etc.)
- Large states where full comparison is expensive
- Need custom validation beyond equality

### Pattern 3: KeyPath Assertions

**Best for:** Single property validations and concise tests.

**Requirements:** Property must be Equatable.

```swift
@MainActor
final class KeyPathTests: XCTestCase {
    func testSingleProperty() async {
        let store = TestStore(
            initialState: CounterFeature.State(),
            feature: CounterFeature()
        )

        // Concise syntax
        await store.send(.increment, \.count, 1)
        await store.send(.increment, \.count, 2)

        // With labels (more explicit)
        await store.send(.increment, expecting: \.count, toBe: 3)
    }

    func testNestedProperty() async {
        await store.send(
            .updateUser,
            \.user.name,
            "Bob"
        )
    }
}
```

**Benefits:**
- Most concise syntax
- Fast to write
- Clear intent

**When to use:**
- Validating single properties
- Quick unit tests
- Property-focused testing

## Testing Async Operations

### With Task IDs

```swift
struct DataFeature: StoreFeature {
    @Observable
    final class State {
        var isLoading = false
        var data: [String] = []
    }

    enum Action: Sendable {
        case loadData
        case dataLoaded([String])
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .loadData:
                state.isLoading = true
                return .run(id: "load-data") {
                    let data = try await fetchData()
                    await store.send(.dataLoaded(data))
                }

            case .dataLoaded(let items):
                state.data = items
                state.isLoading = false
                return .none
            }
        }
    }
}

@MainActor
final class DataTests: XCTestCase {
    func testLoadData() async {
        let store = TestStore(
            initialState: DataFeature.State(),
            feature: DataFeature()
        )

        // TestStore executes tasks synchronously
        await store.send(.loadData) { state in
            state.isLoading = true
        }

        // If task dispatches completion action, it executes immediately
        await store.send(.dataLoaded(["item1", "item2"])) { state in
            state.data = ["item1", "item2"]
            state.isLoading = false
        }
    }
}
```

### Testing Task Cancellation

```swift
func testCancellation() async {
    let store = TestStore(
        initialState: DataFeature.State(),
        feature: DataFeature()
    )

    await store.send(.startTask) { state in
        state.isLoading = true
    }

    await store.send(.cancelTask) { state in
        state.isLoading = false
    }
}
```

## Error Handling Tests

### With onError Handler

```swift
struct NetworkFeature: StoreFeature {
    @Observable
    final class State {
        var errorMessage: String?
    }

    enum Action: Sendable {
        case fetch
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .fetch:
                return .run(id: "fetch") {
                    try await performRequest()
                }
                .catch { error, state in
                    state.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

@MainActor
final class NetworkTests: XCTestCase {
    func testErrorHandling() async {
        let store = TestStore(
            initialState: NetworkFeature.State(),
            feature: NetworkFeature()
        )

        // Inject error via mock
        await store.send(.fetch, assert: { state in
            XCTAssertNotNil(state.errorMessage)
        })
    }
}
```

## Integration Testing with Store

For integration tests, use production ``Store`` instead of TestStore:

```swift
@MainActor
final class IntegrationTests: XCTestCase {
    func testRealStore() async {
        let store = Store(
            initialState: CounterFeature.State(),
            feature: CounterFeature()
        )

        await store.send(.increment).value
        XCTAssertEqual(store.state.count, 1)

        await store.send(.increment).value
        XCTAssertEqual(store.state.count, 2)
    }
}
```

## Action History Validation

TestStore tracks all dispatched actions:

```swift
func testActionSequence() async {
    let store = TestStore(
        initialState: Feature.State(),
        feature: Feature()
    )

    await store.send(.action1)
    await store.send(.action2)
    await store.send(.action3)

    XCTAssertEqual(store.actionHistory.count, 3)

    // Verify sequence
    if case .action1 = store.actionHistory[0] {} else {
        XCTFail("Expected action1")
    }
}
```

## Dependency Injection for Testing

Inject dependencies through feature initializer:

```swift
struct APIFeature: StoreFeature {
    let apiClient: APIClientProtocol

    @Observable
    final class State {
        var data: String?
    }

    enum Action: Sendable {
        case fetch
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .fetch:
                return .run(id: "fetch") {
                    let data = try await apiClient.fetch()
                    await store.send(.dataLoaded(data))
                }
            }
        }
    }
}

// In tests:
let mockClient = MockAPIClient()
let store = TestStore(
    initialState: APIFeature.State(),
    feature: APIFeature(apiClient: mockClient)
)
```

## Performance Testing

Test throughput and latency:

```swift
func testPerformance() async {
    let store = Store(
        initialState: Feature.State(),
        feature: Feature()
    )

    let startTime = Date()

    for _ in 0..<10_000 {
        await store.send(.increment).value
    }

    let duration = Date().timeIntervalSince(startTime)
    let throughput = 10_000.0 / duration

    XCTAssertGreaterThan(throughput, 40_000) // 40k+ actions/sec
}
```

## Best Practices

### 1. Choose the Right Pattern

- **Full state**: Small, Equatable states
- **Custom assertions**: Complex or non-Equatable states
- **KeyPath**: Single property validations

### 2. Test State Changes, Not Implementation

```swift
// ✅ Good - test observable behavior
await store.send(.increment) { state in
    state.count = 1
}

// ❌ Bad - testing implementation details
// verify internal function calls
```

### 3. Use Descriptive Test Names

```swift
// ✅ Good
func testIncrementIncreasesCountByOne() async

// ❌ Bad
func testIncrement() async
```

### 4. Test Edge Cases

```swift
func testDecrementBelowZeroClampedAtZero() async {
    let store = TestStore(
        initialState: CounterFeature.State(count: 0),
        feature: CounterFeature()
    )

    await store.send(.decrement) { state in
        state.count = 0  // Stays at 0
    }
}
```

### 5. Isolate Tests

Each test should be independent:

```swift
// ✅ Good - fresh store per test
func testFeature() async {
    let store = TestStore(...)
    // test code
}

// ❌ Bad - shared store across tests
class Tests: XCTestCase {
    let store = TestStore(...)  // ⚠️ Shared state
}
```

## See Also

- ``TestStore``
- ``AssertionProvider``
- ``Store``
- <doc:Architecture>
