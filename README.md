# ViewFeature

Modern state management for Swift 6.2 with async/await, automatic MainActor isolation, and SwiftUI integration.

[![Swift Version](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%20|%20macOS%20|%20watchOS%20|%20tvOS-lightgrey.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Features

- 🎯 **Modern Swift**: Built with Swift 6.2, async/await, and strict concurrency
- 🛡️ **Thread-Safe by Default**: Automatic MainActor isolation for `@Observable` state
- ⚡ **Type-Safe**: Leverages Swift's type system for compile-time safety
- 🔄 **Reactive**: Seamless SwiftUI integration with `@Observable`
- 🏗 **SOLID Architecture**: Clean separation of concerns following SOLID principles
- 🧪 **Flexible Testing**: 3 testing patterns supporting both Equatable and non-Equatable states
- ✅ **100% Tested**: 267 tests with comprehensive coverage
- 📦 **Lightweight**: Minimal dependencies (only swift-log)
- 🚀 **Production-Ready**: Battle-tested integration and performance tests

## Why ViewFeature?

### The Evolution of Swift State Management

Swift and SwiftUI have evolved significantly:

**The Landscape Has Changed**
- ✨ **Swift 6.2** brings default MainActor isolation for @Observable
- ✨ **@Observable** replaces ObservableObject (but requires classes)
- ✨ **async/await** is now the standard for async operations
- ✨ **Strict concurrency** eliminates data races at compile time
- ✨ **SwiftUI's maturity** means built-in state management is powerful

Traditional Redux-style libraries were designed before these features existed. They made sensible choices for their time:
- Struct-based state (immutability, value semantics)
- Combine-based effects (async patterns of 2019-2020)
- Manual thread-safety management

### ViewFeature's Approach

We embrace modern Swift while learning from proven architectures:

**Built for Swift 6.2**
- 🟢 **`@Observable` State** - Native SwiftUI observation
- 🟢 **Automatic MainActor** - No manual `@MainActor` annotations needed
- 🟢 **Compile-time safety** - Data races caught at compile time, not runtime
- 🟢 **async/await** - Native concurrency, no Combine wrappers
- 🟢 **Pragmatic Structure** - Features, not forced hierarchies

```swift
// ViewFeature - Clean and safe
struct UserFeature: Feature {
    @Observable  // Automatically MainActor in Swift 6.2 ✨
    final class State {
        var user: User?
        var isLoading = false
        // No @MainActor needed - it's the default!
    }

    enum Action: Sendable {
        case load
        case loaded(User)
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .load:
                state.isLoading = true  // ✅ Always safe on MainActor
                return .run(id: "load") {
                    let user = try await api.fetchUser()
                    await store.send(.loaded(user))  // ✅ Automatically MainActor
                }
            case .loaded(let user):
                state.user = user
                state.isLoading = false
                return .none
            }
        }
    }
}

// Compare: Traditional approach
@MainActor  // ⚠️ Must remember to add this
class UserViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false

    func load() async {
        // Easy to forget await MainActor.run { ... }
        isLoading = true
        let user = try? await api.fetchUser()
        self.user = user  // ⚠️ Is this on MainActor?
        isLoading = false
    }
}
```

### Thread Safety by Default

**Swift 6.2's automatic MainActor isolation means:**

```swift
struct CounterFeature: Feature {
    @Observable
    final class State {
        var count = 0  // Guaranteed MainActor access
    }

    enum Action: Sendable {
        case increment
        case backgroundIncrement
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .increment:
                // ✅ On MainActor - safe to mutate state
                state.count += 1
                return .none

            case .backgroundIncrement:
                return .run(id: "bg") {
                    // Background work here
                    await Task.sleep(for: .seconds(1))

                    // ✅ store.send automatically switches to MainActor
                    await store.send(.increment)
                }
            }
        }
    }
}

// SwiftUI integration is naturally safe
struct CounterView: View {
    @State private var store = Store(...)

    var body: some View {
        // ✅ No isolation warnings - View and State are both MainActor
        Text("\(store.state.count)")
    }
}
```

### Key Advantages

**🛡️ Compile-Time Safety**
```swift
// This won't compile - caught at build time!
Task.detached {
    store.state.count += 1  // ❌ Error: state is MainActor-isolated
}

// Correct way - explicit isolation
Task.detached {
    await store.send(.increment)  // ✅ Properly isolated
}
```

**🎯 Natural SwiftUI Integration**
```swift
// Everything just works - no isolation friction
struct MyView: View {
    @State private var store = Store(...)

    var body: some View {
        VStack {
            Text("\(store.state.value)")  // ✅ Safe
            Button("Update") {
                store.send(.update)  // ✅ Safe
            }
        }
        .task {
            await store.send(.load).value  // ✅ Safe async
        }
    }
}
```

**⚡ Zero Boilerplate Threading**
```swift
// Old way - manual threading
@MainActor
class ViewModel: ObservableObject {
    @Published var data: [Item] = []

    func load() {
        Task {
            let items = await api.fetch()
            await MainActor.run {  // ⚠️ Easy to forget!
                self.data = items
            }
        }
    }
}

// ViewFeature way - automatic
struct Feature: Feature {
    @Observable
    final class State {  // Automatically MainActor
        var data: [Item] = []
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            case .load:
                return .run(id: "load") {
                    let items = await api.fetch()
                    await store.send(.loaded(items))  // ✅ Automatic MainActor
                }
        }
    }
}
```

### vs. Plain `@Observable` + ViewModel

| Feature | ViewFeature | @Observable + ViewModel |
|---------|-------------|-------------------------|
| Learning curve | Medium | Low |
| Thread safety | Automatic (Swift 6.2) | Manual `@MainActor` needed |
| Testability | Excellent (pure functions) | Good (needs mocking) |
| Predictability | High (explicit actions) | Medium (implicit mutations) |
| Data race protection | Compile-time | Runtime (if you forget `@MainActor`) |
| Debugging | Action logs, time-travel* | Standard debugging |
| Team consistency | Enforced patterns | Varies by developer |
| Complex flows | Scales well | Can get messy |

*Coming soon

### When to Use ViewFeature

**✅ Great fit:**
- Building with **Swift 6.2** and latest SwiftUI
- Complex business logic spanning multiple views
- Need predictable, testable state transitions
- Want compile-time thread safety without boilerplate
- Team projects requiring architectural consistency
- Apps with intricate async workflows

**❌ Overkill for:**
- Simple CRUD apps
- Single-view utilities
- Prototypes or MVPs
- Projects stuck on Swift 6.0/6.1 (requires manual `@MainActor`)
- When SwiftUI's built-in state management is sufficient

**Rule of thumb:** If you're on Swift 6.2 and find yourself coordinating complex state across views or managing intricate async flows, ViewFeature's automatic safety and architectural consistency will save you time and bugs.

## Installation

Add ViewFeature to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ViewFeature/ViewFeature.git", from: "0.1.0")
]
```

Or in Xcode: File → Add Package Dependencies

## Quick Start

```swift
import ViewFeature

// 1. Define your feature with nested State and Action
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
        case asyncIncrement
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

            case .asyncIncrement:
                return .run(id: "increment") {
                    try await Task.sleep(for: .seconds(1))
                    await store.send(.increment)
                }
            }
        }
    }
}

// 2. Use in SwiftUI
struct CounterView: View {
    @State private var store = Store(
        initialState: CounterFeature.State(),
        feature: CounterFeature()
    )

    var body: some View {
        VStack {
            Text("\(store.state.count)")
                .font(.largeTitle)

            HStack {
                Button("−") { store.send(.decrement) }
                Button("+") { store.send(.increment) }
                Button("Async +") { store.send(.asyncIncrement) }
            }
        }
    }
}
```

## Architecture

ViewFeature follows a unidirectional data flow with **MainActor-based state**:

```
┌─────────────┐ Action ┌──────────────┐
│    View     │─────▶│    Store     │ @MainActor
│ (SwiftUI)   │      │              │
└─────────────┘      └──────────────┘
      ▲                      │
      │ State                │
      │                      ▼
      │              ┌──────────────┐
      └──────────────│ @Observable  │ @MainActor (Swift 6.2)
                     │    State     │
                     └──────────────┘
                            │
                            ▼
                     ┌──────────────┐
                     │ActionHandler │
                     │  + Effects   │
                     └──────────────┘
```

### Core Components

#### Store
The main container that:
- Holds the current state
- Processes actions through ActionHandler
- Manages side effects via TaskManager
- Observes state changes with @Observable

#### ActionHandler
Defines how actions transform state:
- Pure state transformations
- Returns `ActionTask` for side effects
- Supports middleware for cross-cutting concerns

#### ActionTask
Represents side effects:
- `.none` - No side effects
- `.run(id:operation:)` - Execute async operations
- `.cancel(id:)` - Cancel running tasks

#### TaskManager
Manages concurrent task execution:
- Task lifecycle management
- Cancellation support
- Error handling

## Usage Examples

### Async Operations with Error Handling

```swift
struct DataFeature: Feature {
    @Observable
    final class State {
        var isLoading = false
        var data: [Item] = []
    }

    enum Action: Sendable {
        case loadData
        case cancelLoad
        case dataLoaded([Item])
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .loadData:
                state.isLoading = true
                return .run(id: "load-data") {
                    let data = try await apiClient.fetch()
                    await store.send(.dataLoaded(data))
                }
                .catch { error, state in
                    state.isLoading = false
                    state.errorMessage = error.localizedDescription
                }

            case .cancelLoad:
                state.isLoading = false
                return .cancel(id: "load-data")

            case .dataLoaded(let items):
                state.data = items
                state.isLoading = false
                return .none
            }
        }
    }
}
```

### Network Requests

```swift
struct NetworkFeature: Feature {
    @Observable
    final class State {
        var isLoading = false
        var errorMessage: String?
    }

    enum Action: Sendable {
        case fetch
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .fetch:
                state.isLoading = true
                state.errorMessage = nil
                return .run(id: "fetch") {
                    try await networkCall()
                }
                .catch { error, state in
                    state.errorMessage = error.localizedDescription
                    state.isLoading = false
                }
            }
        }
    }
}
```

## Middleware

ViewFeature supports middleware for cross-cutting concerns like logging, analytics, and validation.

### Using Built-in Middleware

```swift
struct MyFeature: Feature {
    @Observable
    final class State {
        var count = 0
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
        .use(LoggingMiddleware(category: "MyFeature"))
    }
}
```

### Creating Custom Middleware

Create custom middleware by conforming to `ActionMiddleware`:

```swift
struct AnalyticsMiddleware: ActionMiddleware {
    func beforeAction<Action, State>(action: Action, state: State) async throws {
        // Track action start
        Analytics.track("action_started", properties: ["action": "\(action)"])
    }

    func afterAction<Action, State>(
        action: Action,
        state: State,
        result: ActionTask<Action, State>,
        duration: TimeInterval
    ) async throws {
        // Track action completion
        Analytics.track("action_completed", properties: [
            "action": "\(action)",
            "duration": duration
        ])
    }

    func onError<Action, State>(
        error: Error,
        action: Action,
        state: State
    ) async {
        // Track errors
        Analytics.track("action_error", properties: [
            "action": "\(action)",
            "error": "\(error)"
        ])
    }
}
```

### Composing Multiple Middleware

```swift
struct MyFeature: Feature {
    // ...
    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            // Action logic
        }
        .use(AnalyticsMiddleware())
        .use(LoggingMiddleware(category: "MyFeature"))
    }
}
```

## Testing

ViewFeature provides straightforward testing using Swift Testing framework with the production `Store` directly.

### Pattern 1: Basic Property Testing

Test individual state properties after actions complete:

```swift
import Testing
@testable import ViewFeature

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
            }
        }
    }
}

@MainActor
@Suite struct CounterTests {
    @Test func increment() async {
        let store = Store(
            initialState: CounterFeature.State(count: 0),
            feature: CounterFeature()
        )

        // Wait for action to complete
        await store.send(.increment).value

        // Verify state
        #expect(store.state.count == 1)
    }

    @Test func multipleActions() async {
        let store = Store(
            initialState: CounterFeature.State(count: 0),
            feature: CounterFeature()
        )

        await store.send(.increment).value
        #expect(store.state.count == 1)

        await store.send(.increment).value
        #expect(store.state.count == 2)

        await store.send(.decrement).value
        #expect(store.state.count == 1)
    }
}
```

### Pattern 2: Multiple Property Testing

Test multiple state properties simultaneously:

```swift
struct AppFeature: Feature {
    @Observable
    final class State {
        var user: User?
        var isLoading = false
        var errorMessage: String?
    }

    enum Action: Sendable {
        case loadUser
        case userLoaded(User)
        case loadFailed(String)
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .loadUser:
                state.isLoading = true
                state.errorMessage = nil
                return .run(id: "load") {
                    let user = try await apiClient.fetchUser()
                    await store.send(.userLoaded(user))
                }
                .catch { error, state in
                    state.errorMessage = error.localizedDescription
                    state.isLoading = false
                }

            case .userLoaded(let user):
                state.user = user
                state.isLoading = false
                return .none

            case .loadFailed(let message):
                state.errorMessage = message
                state.isLoading = false
                return .none
            }
        }
    }
}

@MainActor
@Suite struct AppFeatureTests {
    @Test func loadUserSuccess() async {
        let store = Store(
            initialState: AppFeature.State(),
            feature: AppFeature(apiClient: MockAPIClient(user: User(name: "Alice")))
        )

        // Action sends and waits
        await store.send(.loadUser).value

        // Test multiple properties
        #expect(store.state.user?.name == "Alice")
        #expect(!store.state.isLoading)
        #expect(store.state.errorMessage == nil)
    }

    @Test func loadUserFailure() async {
        let store = Store(
            initialState: AppFeature.State(),
            feature: AppFeature(apiClient: MockAPIClient(shouldFail: true))
        )

        await store.send(.loadUser).value

        // Verify error state
        #expect(store.state.user == nil)
        #expect(!store.state.isLoading)
        #expect(store.state.errorMessage != nil)
    }
}
```

### Pattern 3: Async Task Testing

Test async operations and task lifecycle:

```swift
struct DataFeature: Feature {
    let apiClient: APIClient

    @Observable
    final class State {
        var isLoading = false
        var data: [String] = []
    }

    enum Action: Sendable {
        case loadData
        case dataLoaded([String])
        case cancelLoad
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .loadData:
                state.isLoading = true
                return .run(id: "load-data") {
                    let data = try await apiClient.fetch()
                    await store.send(.dataLoaded(data))
                }
                .catch { error, state in
                    state.isLoading = false
                }

            case .dataLoaded(let items):
                state.data = items
                state.isLoading = false
                return .none

            case .cancelLoad:
                state.isLoading = false
                return .cancel(id: "load-data")
            }
        }
    }
}

@MainActor
@Suite struct AsyncTests {
    @Test func asyncTaskCompletion() async {
        let store = Store(
            initialState: DataFeature.State(),
            feature: DataFeature(apiClient: MockAPIClient(data: ["item1", "item2"]))
        )

        // Store.send() waits for background tasks to complete
        await store.send(.loadData).value

        // Task is guaranteed to be complete - no Task.sleep needed!
        #expect(!store.state.isLoading)
        #expect(store.state.data == ["item1", "item2"])
        #expect(store.runningTaskCount == 0)
    }

    @Test func taskCancellation() async {
        let store = Store(
            initialState: DataFeature.State(),
            feature: DataFeature(apiClient: SlowMockAPIClient())
        )

        // Start task
        store.send(.loadData)

        // Verify task is running
        #expect(store.isTaskRunning(id: "load-data"))

        // Cancel it
        await store.send(.cancelLoad).value

        // Verify cancellation
        #expect(!store.isTaskRunning(id: "load-data"))
        #expect(!store.state.isLoading)
    }
}
```

## Best Practices

### State Design

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

### Working with Background Tasks

Actions run on MainActor, but effects can spawn background work:

```swift
return .run(id: "fetch") {
    // This closure can do background work
    let data = await heavyComputation()  // Off main thread

    // Send results back to MainActor
    await store.send(.dataLoaded(data))  // Automatically MainActor
}
```

## Migration Guides

### From The Composable Architecture (TCA)

**Key differences:**
- State is `@Observable class` instead of `struct`
- Effects use async/await instead of `Effect<Action>`
- No `Reducer` protocol, use `Feature`
- No automatic reducer composition tree

```swift
// TCA
struct Feature: Reducer {
    struct State: Equatable {  // struct
        var count = 0
    }
    enum Action { case increment }

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .increment:
            state.count += 1
            return .none
        }
    }
}

// ViewFeature
struct Feature: Feature {
    @Observable
    final class State {  // class with @Observable
        var count = 0
    }
    enum Action: Sendable { case increment }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in  // no inout!
            switch action {
            case .increment:
                state.count += 1
                return .none
            }
        }
    }
}
```

### From Plain ViewModels

Already using `@Observable` ViewModels? Easy migration:

```swift
// Before: ViewModel
@Observable
final class CounterViewModel {
    var count = 0

    func increment() {
        count += 1
    }

    func asyncIncrement() async {
        try? await Task.sleep(for: .seconds(1))
        count += 1
    }
}

// After: ViewFeature
struct CounterFeature: Feature {
    @Observable
    final class State {
        var count = 0
    }

    enum Action: Sendable {
        case increment
        case asyncIncrement
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .increment:
                state.count += 1
                return .none
            case .asyncIncrement:
                return .run(id: "async") {
                    try await Task.sleep(for: .seconds(1))
                    await store.send(.increment)
                }
            }
        }
    }
}

// Bonus: Now your logic is testable!
```

## Design Philosophy

ViewFeature believes that:

1. **SwiftUI is the tree** - No need to duplicate your view hierarchy with reducer trees
2. **Modern Swift is better** - async/await > Combine, @Observable > ObservableObject
3. **Pragmatism over purity** - Class-based state is fine if it works with the platform
4. **Test what matters** - Flexible assertions over rigid Equatable requirements
5. **Features, not reducers** - Self-contained units that don't need orchestration

We're inspired by Redux and TCA's architectural principles, but rebuilt from scratch for Swift 6.2 and SwiftUI's reality.

## Requirements

- iOS 18.0+ / macOS 15.0+ / watchOS 11.0+ / tvOS 18.0+
- **Swift 6.2+** ⚠️
- Xcode 16.0+

### Why Swift 6.2?

ViewFeature relies on Swift 6.2's **default MainActor isolation** for `@Observable` classes. This provides:

- ✅ Automatic MainActor isolation for State classes
- ✅ Safe SwiftUI integration without explicit `@MainActor` annotations
- ✅ Compile-time thread-safety guarantees

**What this means:**

```swift
// In Swift 6.2+, this State is automatically MainActor-isolated
@Observable
final class State {
    var count = 0  // Always accessed on main thread
}

// No need for explicit @MainActor annotation!
struct MyView: View {
    @State private var store = Store(...)

    var body: some View {
        Text("\(store.state.count)")  // ✅ Safe!
    }
}
```

**If you're on Swift 6.0 or 6.1:**
- Manually add `@MainActor` to your State classes
- Or consider upgrading to Swift 6.2 for the best experience

## Documentation

Full API documentation is available through Swift DocC:

```bash
swift package generate-documentation
```

## Roadmap

- ✅ Core state management
- ✅ Async/await task support
- ✅ Middleware system
- ✅ Comprehensive testing utilities
- ✅ Full documentation
- 🔄 Enhanced debugging tools
- 🔄 Time-travel debugging
- 🔄 State persistence
- 🔄 SwiftUI bindings helpers
- 🔄 Performance profiling tools

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

ViewFeature is available under the MIT license. See [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)
- Built with [swift-log](https://github.com/apple/swift-log) for structured logging
- Designed for the Swift community

## Resources

- 📖 Documentation: In-code documentation and this README
- 🐛 Issues: [GitHub Issues](https://github.com/ViewFeature/ViewFeature/issues)
- 💬 Discussions: [GitHub Discussions](https://github.com/ViewFeature/ViewFeature/discussions)

---

Built with ❤️ using Swift 6.2 and modern concurrency

Version 0.1.0 | © 2025
