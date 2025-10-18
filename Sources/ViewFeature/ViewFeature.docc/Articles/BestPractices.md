# Best Practices

Recommended patterns and practices for building robust ViewFeature applications.

## Overview

This guide covers best practices for designing features, managing state, handling side effects, and testing your ViewFeature applications effectively.

## State Design

### Keep State MainActor-Isolated

In Swift 6.2, `@Observable` classes are automatically MainActor-isolated - embrace this default:

**✅ Do: Keep State MainActor-isolated (automatic in Swift 6.2)**
```swift
@Observable
final class State {
    var items: [Item] = []
    var isLoading = false
}
```

**❌ Don't: Make State non-isolated**
```swift
nonisolated @Observable  // ⚠️ Breaks SwiftUI integration
final class State {
    var items: [Item] = []
}
```

### State Should Be Observable Classes

Use `@Observable` classes for state to ensure SwiftUI observability:

**✅ Do: Use @Observable class**
```swift
@Observable
final class State {
    var count = 0
    var user: User?
}
```

**❌ Don't: Use structs**
```swift
struct State {  // ⚠️ Won't work with @Observable
    var count = 0
}
```

### Keep State Focused

Each feature should have a focused state that represents a single domain:

**✅ Do: Focused state**
```swift
struct UserProfileFeature: Feature {
    @Observable
    final class State {
        var user: User?
        var isEditing = false
        var isSaving = false
    }
}
```

**❌ Don't: Mix unrelated domains**
```swift
struct AppFeature: Feature {
    @Observable
    final class State {
        var user: User?
        var cart: ShoppingCart?  // Different domain
        var notifications: [Notification] = []  // Different domain
    }
}
```

### Provide Sensible Defaults

Always provide default values or initializers:

**✅ Do: Provide defaults**
```swift
@Observable
final class State {
    var items: [Item] = []  // Empty array default
    var isLoading = false   // False default
    var errorMessage: String?  // nil is fine for optional

    init(items: [Item] = []) {
        self.items = items
    }
}
```

## Action Design

### Use Descriptive Action Names

Action names should clearly describe what happened, not what should happen:

**✅ Do: Descriptive names**
```swift
enum Action: Sendable {
    case userTappedLoginButton
    case loginResponseReceived(Result<User, Error>)
    case userDismissedAlert
}
```

**❌ Don't: Vague names**
```swift
enum Action: Sendable {
    case action1
    case doLogin
    case handle
}
```

### Actions Must Be Sendable

All actions must conform to `Sendable` for thread safety:

**✅ Do: Sendable actions**
```swift
enum Action: Sendable {
    case increment
    case dataLoaded([String])  // Array is Sendable
}
```

**❌ Don't: Non-Sendable types**
```swift
enum Action {  // ⚠️ Missing Sendable
    case dataLoaded(NSMutableArray)  // ⚠️ Not Sendable
}
```

### Group Related Actions

Use associated values to group related actions:

**✅ Do: Grouped actions**
```swift
enum Action: Sendable {
    case user(UserAction)
    case cart(CartAction)
    case checkout(CheckoutAction)
}

enum UserAction: Sendable {
    case login
    case logout
    case updateProfile(User)
}
```

## Working with Background Tasks

### Always Use Task IDs

Provide unique IDs for all async tasks to enable cancellation:

**✅ Do: Use task IDs**
```swift
case .loadData:
    state.isLoading = true
    return .run(id: "load-data") { state in
        let data = try await apiClient.fetch()
        state.data = data
        state.isLoading = false
    }
```

**❌ Don't: Omit IDs**
```swift
case .loadData:
    return .run(id: "") {  // ⚠️ Empty ID
        // ...
    }
```

### Handle Background Work Properly

Actions run on MainActor, but effects can spawn background work:

**✅ Do: Background work in effects**
```swift
case .processImage:
    return .run(id: "process") {
        // This closure can do background work
        let processed = await heavyImageProcessing()  // Off main thread

        // Send results back to MainActor
        await store.send(.imageProcessed(processed))  // Automatically MainActor
    }
```

**❌ Don't: Block MainActor**
```swift
case .processImage:
    // ⚠️ Blocks MainActor
    state.processedImage = heavyImageProcessing()
    return .none
```

### Always Handle Errors

Use `.catch` to handle errors gracefully:

**✅ Do: Handle errors**
```swift
case .loadData:
    state.isLoading = true
    return .run(id: "load") { state in
        let data = try await apiClient.fetch()
        state.data = data
        state.isLoading = false
    }
    .catch { error, state in
        state.errorMessage = error.localizedDescription
        state.isLoading = false
    }
```

**❌ Don't: Ignore errors**
```swift
case .loadData:
    return .run(id: "load") {
        let data = try? await apiClient.fetch()  // ⚠️ Silently fails
        // ...
    }
```

### Cancel Tasks When Needed

Cancel running tasks when they're no longer needed:

**✅ Do: Cancel appropriately**
```swift
case .cancelSearch:
    state.isSearching = false
    return .cancel(id: "search")

case .userNavigatedAway:
    return .cancel(id: "long-running-task")
```

## Dependency Injection

### Inject Dependencies via Initializer

Always inject dependencies through the feature initializer:

**✅ Do: Initializer injection**
```swift
struct UserFeature: Feature {
    let apiClient: APIClient
    let database: Database

    init(
        apiClient: APIClient = .production,
        database: Database = .production
    ) {
        self.apiClient = apiClient
        self.database = database
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            // Use self.apiClient and self.database
        }
    }
}
```

**❌ Don't: Hard-code dependencies**
```swift
struct UserFeature: Feature {
    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            // ⚠️ Hard-coded, can't test
            let data = try await ProductionAPIClient().fetch()
        }
    }
}
```

### Use Protocols for Dependencies

Define protocol-based dependencies for testability:

**✅ Do: Protocol-based**
```swift
protocol APIClient: Sendable {
    func fetch() async throws -> [Item]
}

struct ProductionAPIClient: APIClient {
    func fetch() async throws -> [Item] {
        // Real implementation
    }
}

struct MockAPIClient: APIClient {
    let mockData: [Item]

    func fetch() async throws -> [Item] {
        mockData
    }
}
```

## Testing Best Practices

### Always Wait for Action Completion

**✅ Do: Wait for completion**
```swift
@Test func loadData() async {
    let store = Store(...)

    await store.send(.loadData).value  // Wait for completion

    #expect(!store.state.isLoading)
}
```

**❌ Don't: Fire-and-forget**
```swift
@Test func loadData() async {
    let store = Store(...)

    store.send(.loadData)  // ⚠️ May not complete

    #expect(!store.state.isLoading)  // ⚠️ Flaky test
}
```

### Test Behavior, Not Implementation

**✅ Do: Test observable behavior**
```swift
@Test func increment() async {
    let store = Store(...)

    await store.send(.increment).value

    #expect(store.state.count == 1)  // Test state change
}
```

**❌ Don't: Test implementation details**
```swift
@Test func increment() async {
    // ⚠️ Testing internal implementation
    #expect(feature.internalCounter == 1)
}
```

### Use Descriptive Test Names

**✅ Do: Clear test names**
```swift
@Test func incrementIncreasesCountByOne() async
@Test func loadDataSetsIsLoadingToTrue() async
@Test func decrementAtZeroStaysAtZero() async
```

**❌ Don't: Vague names**
```swift
@Test func test1() async
@Test func testIncrement() async
@Test func testFeature() async
```

### Isolate Tests

Each test should create its own store:

**✅ Do: Fresh store per test**
```swift
@Suite struct CounterTests {
    @Test func increment() async {
        let store = Store(...)  // Fresh store
        // Test code
    }

    @Test func decrement() async {
        let store = Store(...)  // Fresh store
        // Test code
    }
}
```

**❌ Don't: Share store across tests**
```swift
@Suite struct CounterTests {
    let store = Store(...)  // ⚠️ Shared state causes issues

    @Test func increment() async {
        // Tests affect each other
    }
}
```

## Feature Organization

### One Feature Per File

Keep each feature in its own file:

```
Features/
├── User/
│   ├── UserFeature.swift
│   ├── UserView.swift
│   └── UserTests.swift
├── Cart/
│   ├── CartFeature.swift
│   ├── CartView.swift
│   └── CartTests.swift
└── Checkout/
    ├── CheckoutFeature.swift
    ├── CheckoutView.swift
    └── CheckoutTests.swift
```

### Nest State and Action

Nest State and Action types within the feature:

**✅ Do: Nested types**
```swift
struct UserFeature: Feature {
    @Observable
    final class State {
        // ...
    }

    enum Action: Sendable {
        // ...
    }

    func handle() -> ActionHandler<Action, State> {
        // ...
    }
}
```

**❌ Don't: Top-level types**
```swift
@Observable
final class UserState {  // ⚠️ Pollutes namespace
    // ...
}

enum UserAction: Sendable {  // ⚠️ Pollutes namespace
    // ...
}
```

## Performance Considerations

### Avoid Expensive Computed Properties

Store derived data instead of computing it repeatedly:

**✅ Do: Store derived data**
```swift
@Observable
final class State {
    var items: [Item] = []
    var filteredItems: [Item] = []  // Cached

    // Update filteredItems when items change
}
```

**❌ Don't: Expensive computed properties**
```swift
@Observable
final class State {
    var items: [Item] = []

    // ⚠️ Recomputed on every access
    var filteredItems: [Item] {
        items.filter { $0.isActive }.sorted()
    }
}
```

### Debounce Frequent Actions

Debounce actions that fire frequently:

**✅ Do: Debounce search**
```swift
case .searchTextChanged(let text):
    state.searchText = text
    return .run(id: "search") { state in
        try await Task.sleep(for: .milliseconds(300))
        // Perform search with state.searchText
        let results = try await searchAPI.search(state.searchText)
        state.searchResults = results
    }
```

### Automatic Task Cancellation

ViewFeature automatically cancels previous tasks when you start a new task with the same ID:

**✅ Do: Use same task ID (automatic cancellation)**
```swift
case .searchTextChanged(let text):
    state.searchText = text
    // Starting a new task with id "search" automatically cancels the previous one
    return .run(id: "search") { state in
        try await Task.sleep(for: .milliseconds(300))
        // Perform search with state.searchText
        let results = try await searchAPI.search(state.searchText)
        state.searchResults = results
    }
```

> Note: When you start a task with an ID that's already running, ViewFeature automatically cancels the old task before starting the new one. This makes debouncing patterns simple and safe.

## Middleware Usage

### Use Middleware for Cross-Cutting Concerns

Apply middleware for logging, analytics, or validation:

**✅ Do: Use middleware**
```swift
func handle() -> ActionHandler<Action, State> {
    ActionHandler { action, state in
        // Business logic
    }
    .use(LoggingMiddleware(category: "UserFeature"))
    .use(AnalyticsMiddleware())
}
```

### Keep Middleware Focused

Each middleware should have a single responsibility:

**✅ Do: Focused middleware**
```swift
struct LoggingMiddleware: ActionMiddleware {
    // Only logging
}

struct AnalyticsMiddleware: ActionMiddleware {
    // Only analytics
}
```

**❌ Don't: God middleware**
```swift
struct EverythingMiddleware: ActionMiddleware {
    // ⚠️ Logging, analytics, validation, caching...
}
```

## Task Composition

### Choose the Right Composition Primitive

Use `.merge()` for parallel execution and `.concatenate()` for sequential execution:

**✅ Do: Use merge for independent operations**
```swift
case .loadDashboard:
    // These can run in parallel - no dependencies
    return .merge(
        .run { state in
            state.users = try await api.fetchUsers()
        },
        .run { state in
            state.posts = try await api.fetchPosts()
        },
        .run { state in
            state.notifications = try await api.fetchNotifications()
        }
    )
```

**✅ Do: Use concatenate for dependent operations**
```swift
case .submitOrder:
    // These must run in sequence - each depends on previous
    return .concatenate(
        .run { state in
            state.orderId = try await api.createOrder()
        },
        .run { state in
            try await api.processPayment(state.orderId!)
        },
        .run { state in
            try await api.sendConfirmation(state.orderId!)
        }
    )
```

**❌ Don't: Use concatenate when merge would work**
```swift
case .loadDashboard:
    // ⚠️ This is slow! These are independent and should use .merge()
    return .concatenate(
        .run { state in state.users = try await api.fetchUsers() },
        .run { state in state.posts = try await api.fetchPosts() }
    )
```

### Prefer Merge for Better Performance

When operations are independent, always prefer `.merge()` for better performance:

**✅ Do: Parallel for speed**
```swift
// Completes in ~500ms (max of all tasks)
return .merge(
    .run { try await Task.sleep(for: .milliseconds(100)) },
    .run { try await Task.sleep(for: .milliseconds(500)) },
    .run { try await Task.sleep(for: .milliseconds(200)) }
)
```

**❌ Don't: Sequential when unnecessary**
```swift
// ⚠️ Takes ~800ms (sum of all tasks)
return .concatenate(
    .run { try await Task.sleep(for: .milliseconds(100)) },
    .run { try await Task.sleep(for: .milliseconds(500)) },
    .run { try await Task.sleep(for: .milliseconds(200)) }
)
```

### Use Nested Composition for Complex Workflows

Combine both primitives for sophisticated workflows:

**✅ Do: Nest composition for clarity**
```swift
case .initialize:
    return .concatenate(
        // Step 1: Show loading
        .run { state in state.isLoading = true },

        // Step 2: Load data in parallel
        .merge(
            .run { state in state.profile = try await api.fetchProfile() },
            .run { state in state.settings = try await api.fetchSettings() },
            .run { state in state.cache = try await cache.load() }
        ),

        // Step 3: Process (only after all parallel tasks complete)
        .run { state in
            state.processedData = process(state.profile, state.settings)
        },

        // Step 4: Hide loading
        .run { state in state.isLoading = false }
    )
```

### Handle Errors in Composition

Add error handling to composed tasks:

**✅ Do: Add catch to composition**
```swift
case .syncData:
    return .merge(
        .run { state in state.local = try await syncLocal() },
        .run { state in state.remote = try await syncRemote() }
    )
    .catch { error, state in
        state.syncError = error.localizedDescription
        state.lastSyncFailed = true
    }
```

**❌ Don't: Forget error handling**
```swift
case .syncData:
    // ⚠️ Errors will crash if not caught
    return .merge(
        .run { state in state.local = try await syncLocal() },
        .run { state in state.remote = try await syncRemote() }
    )
```

### Use Array-Based Composition for Dynamic Lists

When the number of tasks is dynamic, use array-based composition:

**✅ Do: Array-based for dynamic tasks**
```swift
case .loadUsers(let userIDs):
    let fetchTasks = userIDs.map { id in
        ActionTask.run { state in
            state.users[id] = try await api.fetchUser(id: id)
        }
    }
    return .merge(fetchTasks)
```

**❌ Don't: Hardcode when dynamic**
```swift
case .loadUsers(let userIDs):
    // ⚠️ Only works for exactly 3 users
    return .merge(
        .run { state in state.users[userIDs[0]] = try await api.fetchUser(id: userIDs[0]) },
        .run { state in state.users[userIDs[1]] = try await api.fetchUser(id: userIDs[1]) },
        .run { state in state.users[userIDs[2]] = try await api.fetchUser(id: userIDs[2]) }
    )
```

### Combine with Cancellation

Composed tasks work seamlessly with cancellation:

**✅ Do: Make composed tasks cancellable**
```swift
case .searchAll(let query):
    return .merge(
        .run { state in state.userResults = try await searchUsers(query) },
        .run { state in state.postResults = try await searchPosts(query) },
        .run { state in state.tagResults = try await searchTags(query) }
    )
    .cancellable(id: "search-all", cancelInFlight: true)

case .cancelSearch:
    return .cancel(id: "search-all")  // Cancels all parallel searches
```

### Keep Composition Shallow

Avoid deeply nested composition for readability:

**✅ Do: Keep it readable**
```swift
case .initialize:
    return .concatenate(
        initStep1(),
        initStep2(),
        initStep3()
    )

private func initStep2() -> ActionTask<Action, State> {
    .merge(
        .run { state in state.profile = try await api.fetchProfile() },
        .run { state in state.settings = try await api.fetchSettings() }
    )
}
```

**❌ Don't: Deeply nest**
```swift
case .initialize:
    // ⚠️ Hard to read and maintain
    return .concatenate(
        .run { state in state.step = 1 },
        .concatenate(
            .merge(
                .run { /* ... */ },
                .concatenate(
                    .run { /* ... */ },
                    .merge(
                        .run { /* ... */ },
                        .run { /* ... */ }
                    )
                )
            ),
            .run { state in state.step = 2 }
        )
    )
```

## See Also

- <doc:GettingStarted>
- <doc:Architecture>
- <doc:TestingGuide>
- <doc:MigrationGuide>
- ``Store``
- ``Feature``
- ``ActionHandler``
