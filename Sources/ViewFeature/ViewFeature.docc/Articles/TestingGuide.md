# Testing Guide

Comprehensive testing strategies for ViewFeature applications using Swift Testing.

## Overview

ViewFeature testing is straightforward: create a ``Store`` directly, send actions, and verify state changes using Swift Testing's `#expect` macro. No special test utilities are needed.

## Basic Testing Pattern

All tests follow this simple pattern:

```swift
import Testing
@testable import ViewFeature

@MainActor
@Test func incrementAction() async {
  // GIVEN: Create store with initial state
  let store = Store(
    initialState: CounterFeature.State(count: 0),
    feature: CounterFeature()
  )

  // WHEN: Send action and wait for completion
  await store.send(.increment).value

  // THEN: Verify state changes
  #expect(store.state.count == 1)
}
```

### Feature Definition

```swift
struct CounterFeature: Feature {
  @Observable
  final class State {
    var count = 0

    init(count: Int = 0) {
      self.count = count
    }
  }

  enum Action: Sendable {
    case increment
    case decrement
    case reset
  }

  func handle() -> ActionHandler<Action, State> {
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
      }
    }
  }
}
```

## Testing Multiple Actions

```swift
@Test func multipleActions() async {
  let store = Store(
    initialState: CounterFeature.State(count: 5),
    feature: CounterFeature()
  )

  await store.send(.increment).value
  #expect(store.state.count == 6)

  await store.send(.increment).value
  #expect(store.state.count == 7)

  await store.send(.decrement).value
  #expect(store.state.count == 6)

  await store.send(.reset).value
  #expect(store.state.count == 0)
}
```

## Testing Async Operations

### Basic Async Task

```swift
struct DataFeature: Feature {
  let apiClient: APIClient

  @Observable
  final class State {
    var isLoading = false
    var data: [String] = []
    var error: String?
  }

  enum Action: Sendable {
    case loadData
    case dataLoaded([String])
    case loadFailed(Error)
  }

  func handle() -> ActionHandler<Action, State> {
    ActionHandler { action, state in
      switch action {
      case .loadData:
        state.isLoading = true
        return .run(id: "load-data") { state in
          let data = try await apiClient.fetch()
          state.data = data
          state.isLoading = false
        }
        .catch { error, state in
          state.error = error.localizedDescription
          state.isLoading = false
        }

      case .dataLoaded(let items):
        state.data = items
        state.isLoading = false
        return .none

      case .loadFailed(let error):
        state.error = error.localizedDescription
        state.isLoading = false
        return .none
      }
    }
  }
}

@Test func asyncDataLoading() async {
  let mockClient = MockAPIClient(mockData: ["item1", "item2"])
  let store = Store(
    initialState: DataFeature.State(),
    feature: DataFeature(apiClient: mockClient)
  )

  // Send action and wait for completion
  await store.send(.loadData).value

  // Verify final state
  #expect(store.state.data == ["item1", "item2"])
  #expect(!store.state.isLoading)
  #expect(store.state.error == nil)
}
```

### Testing Error Handling

```swift
@Test func errorHandling() async {
  let mockClient = MockAPIClient(shouldFail: true)
  let store = Store(
    initialState: DataFeature.State(),
    feature: DataFeature(apiClient: mockClient)
  )

  await store.send(.loadData).value

  #expect(store.state.data.isEmpty)
  #expect(!store.state.isLoading)
  #expect(store.state.error != nil)
}
```

## Testing Task Cancellation

```swift
struct DownloadFeature: Feature {
  @Observable
  final class State {
    var isDownloading = false
    var progress: Double = 0.0
  }

  enum Action: Sendable {
    case startDownload
    case cancelDownload
    case updateProgress(Double)
  }

  func handle() -> ActionHandler<Action, State> {
    ActionHandler { action, state in
      switch action {
      case .startDownload:
        state.isDownloading = true
        return .run(id: "download") { state in
          for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            try await Task.sleep(for: .milliseconds(100))
            state.progress = progress
          }
          state.isDownloading = false
        }

      case .cancelDownload:
        state.isDownloading = false
        return .cancel(id: "download")

      case .updateProgress(let value):
        state.progress = value
        return .none
      }
    }
  }
}

@Test func taskCancellation() async {
  let store = Store(
    initialState: DownloadFeature.State(),
    feature: DownloadFeature()
  )

  // Start download
  store.send(.startDownload)

  // Wait a bit
  try? await Task.sleep(for: .milliseconds(50))

  // Cancel it
  await store.send(.cancelDownload).value

  // Verify cancellation
  #expect(!store.state.isDownloading)
  #expect(!store.isTaskRunning(id: "download"))
}
```

## Dependency Injection for Testing

Always inject dependencies through feature initializer for testability:

```swift
protocol APIClient: Sendable {
  func fetch() async throws -> [String]
}

struct ProductionAPIClient: APIClient {
  func fetch() async throws -> [String] {
    // Real API call
  }
}

struct MockAPIClient: APIClient {
  let mockData: [String]
  let shouldFail: Bool

  init(mockData: [String] = [], shouldFail: Bool = false) {
    self.mockData = mockData
    self.shouldFail = shouldFail
  }

  func fetch() async throws -> [String] {
    if shouldFail {
      throw NSError(domain: "Test", code: 1)
    }
    return mockData
  }
}

// In production:
let store = Store(
  initialState: DataFeature.State(),
  feature: DataFeature(apiClient: ProductionAPIClient())
)

// In tests:
let store = Store(
  initialState: DataFeature.State(),
  feature: DataFeature(apiClient: MockAPIClient(mockData: ["test"]))
)
```

## Testing Non-Equatable States

You don't need Equatable conformance - just test individual properties:

```swift
@Observable
final class ComplexState {
  var user: User?
  var settings: [String: Any] = [:]  // Not Equatable
  var isLoading = false
}

@Test func nonEquatableState() async {
  let store = Store(
    initialState: ComplexFeature.State(),
    feature: ComplexFeature()
  )

  await store.send(.loadUser).value

  // Test only what matters
  #expect(store.state.user?.name == "Alice")
  #expect(store.state.user?.age == 30)
  #expect(!store.state.isLoading)
  // settings not tested - irrelevant for this test
}
```

## Performance Testing

Test throughput and resource usage:

```swift
@Test func performanceThroughput() async {
  let store = Store(
    initialState: CounterFeature.State(),
    feature: CounterFeature()
  )

  let startTime = Date()
  let actionCount = 10_000

  for _ in 0..<actionCount {
    await store.send(.increment).value
  }

  let duration = Date().timeIntervalSince(startTime)
  let throughput = Double(actionCount) / duration

  #expect(store.state.count == actionCount)
  #expect(throughput > 5_000) // At least 5k actions/sec

  print("Throughput: \(Int(throughput)) actions/second")
}
```

## Integration Testing

For integration tests, test the full workflow:

```swift
@Test func fullUserWorkflow() async {
  let store = Store(
    initialState: AppFeature.State(),
    feature: AppFeature(
      apiClient: MockAPIClient(),
      database: MockDatabase()
    )
  )

  // Step 1: Load initial data
  await store.send(.loadInitialData).value
  #expect(!store.state.isLoading)
  #expect(store.state.data != nil)

  // Step 2: User action
  await store.send(.selectItem("item1")).value
  #expect(store.state.selectedItem == "item1")

  // Step 3: Save changes
  await store.send(.saveChanges).value
  #expect(store.state.isSaving == false)
  #expect(store.state.saveSuccess == true)
}
```

## Testing with Middleware

```swift
@Test func middlewareIntegration() async {
  // Create tracking middleware
  actor ActionTracker {
    var actions: [String] = []
    func append(_ action: String) {
      actions.append(action)
    }
    func getActions() -> [String] {
      actions
    }
  }

  let tracker = ActionTracker()

  struct TrackingMiddleware: ActionMiddleware {
    let id = "TrackingMiddleware"
    let tracker: ActionTracker

    func beforeAction<Action, State>(_ action: Action, state: State) async throws {
      await tracker.append("\(action)")
    }
  }

  // Create store with middleware
  let store = Store(
    initialState: CounterFeature.State(),
    feature: CounterFeature()
  )

  // Note: Middleware attachment would need to be done through ActionHandler
  // This is just an example of testing pattern

  await store.send(.increment).value
  await store.send(.increment).value

  let actions = await tracker.getActions()
  #expect(actions.count == 2)
}
```

## Best Practices

### 1. Always Wait for Completion

```swift
// ✅ Good - wait for action to complete
await store.send(.loadData).value

// ❌ Bad - fire-and-forget can cause race conditions
store.send(.loadData)
```

### 2. Test Behavior, Not Implementation

```swift
// ✅ Good - test observable state changes
await store.send(.increment).value
#expect(store.state.count == 1)

// ❌ Bad - testing implementation details
// Verify internal method calls, private state, etc.
```

### 3. Use Descriptive Test Names

```swift
// ✅ Good - clear what is being tested
@Test func incrementIncreasesCountByOne() async

// ❌ Bad - vague
@Test func testIncrement() async
```

### 4. Test Edge Cases

```swift
@Test func decrementAtZeroStaysAtZero() async {
  let store = Store(
    initialState: CounterFeature.State(count: 0),
    feature: CounterFeature()
  )

  await store.send(.decrement).value
  #expect(store.state.count == 0)  // Clamped at zero
}
```

### 5. Isolate Tests

Each test should create its own store:

```swift
// ✅ Good - fresh store per test
@Test func testFeature() async {
  let store = Store(...)
  // test code
}

// ❌ Bad - shared store across tests
@Suite struct Tests {
  let store = Store(...)  // ⚠️ Shared state causes issues
}
```

### 6. Use Actor for Thread-Safe Mocks

```swift
actor MockDatabase {
  var savedItems: [String] = []

  func save(_ item: String) {
    savedItems.append(item)
  }

  func getSaved() -> [String] {
    savedItems
  }
}

@Test func databaseIntegration() async {
  let mockDB = MockDatabase()
  let store = Store(
    initialState: Feature.State(),
    feature: Feature(database: mockDB)
  )

  await store.send(.saveItem("test")).value

  let saved = await mockDB.getSaved()
  #expect(saved.contains("test"))
}
```

## Common Patterns

### Testing Loading States

```swift
@Test func loadingStates() async {
  let store = Store(
    initialState: DataFeature.State(),
    feature: DataFeature(apiClient: SlowMockClient())
  )

  // Before action
  #expect(!store.state.isLoading)

  // Send action (don't wait)
  let task = store.send(.loadData)

  // During loading (may need a small delay)
  try? await Task.sleep(for: .milliseconds(10))
  #expect(store.state.isLoading)

  // After completion
  await task.value
  #expect(!store.state.isLoading)
  #expect(store.state.data != nil)
}
```

### Testing Debouncing

```swift
@Test func searchDebouncing() async {
  let store = Store(
    initialState: SearchFeature.State(),
    feature: SearchFeature()
  )

  // Rapid searches
  store.send(.searchTextChanged("a"))
  store.send(.searchTextChanged("ab"))
  await store.send(.searchTextChanged("abc")).value

  // Wait for debounce
  try? await Task.sleep(for: .milliseconds(350))

  // Only last search should execute
  #expect(store.state.searchResults.count > 0)
  #expect(store.state.lastSearchedText == "abc")
}
```

## See Also

- ``Store``
- ``Feature``
- ``ActionHandler``
- <doc:Architecture>
