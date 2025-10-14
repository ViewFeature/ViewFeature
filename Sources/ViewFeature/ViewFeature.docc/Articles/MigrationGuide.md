# Migration Guide

Migrate from other state management frameworks to ViewFeature.

## Overview

This guide helps you migrate from popular Swift state management frameworks to ViewFeature, highlighting key differences and migration strategies.

## From The Composable Architecture (TCA)

### Conceptual Mapping

| TCA | ViewFeature | Notes |
|-----|-------------|-------|
| `Reducer` protocol | `Feature` protocol | Similar purpose, different API |
| `Store` | `Store` | Direct equivalent |
| `Effect` | `ActionTask` | Simplified task model |
| `TestStore` | `Store` + Swift Testing | Use production Store for tests |
| `ViewStore` | Not needed | @Observable handles observation |

### Key Differences

#### 1. State Observation

**TCA (ObservableObject):**
```swift
@ObservedObject var viewStore: ViewStoreOf<Feature>
```

**ViewFeature (@Observable):**
```swift
@State private var store = Store(...)
```

ViewFeature uses Swift 5.9+ @Observable, eliminating ViewStore and providing better performance.

#### 2. Reducer Definition

**TCA:**
```swift
struct CounterFeature: Reducer {
    struct State: Equatable {
        var count = 0
    }

    enum Action {
        case increment
    }

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .increment:
            state.count += 1
            return .none
        }
    }
}
```

**ViewFeature:**
```swift
struct CounterFeature: Feature {
    @Observable
    final class State {
        var count = 0
        init(count: Int = 0) { self.count = count }
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
```

**Key changes:**
- State is a class (for @Observable)
- `handle()` instead of `reduce(into:action:)`
- `ActionTask` instead of `Effect`
- Actions must be `Sendable`

#### 3. Side Effects

**TCA:**
```swift
case .fetch:
    return .run { send in
        let data = try await api.fetch()
        await send(.dataLoaded(data))
    }
```

**ViewFeature:**
```swift
case .fetch:
    return .run(id: "fetch") {
        let data = try await api.fetch()
        await store.send(.dataLoaded(data))
    }
```

**Key changes:**
- Explicit task IDs for cancellation
- Direct store access (no `send` parameter)

#### 4. Composition

**TCA:**
Uses `Scope` and `Reducer` composition operators.

**ViewFeature:**
Manual composition through nested stores:

```swift
struct ParentFeature: Feature {
    @Observable
    final class State {
        var child: ChildFeature.State
    }

    enum Action: Sendable {
        case child(ChildFeature.Action)
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .child(let childAction):
                // Manually forward to child
                return .none
            }
        }
    }
}
```

### Migration Strategy

1. **Start with simple features**: Migrate leaf features first
2. **Update state to @Observable class**: Convert structs to classes
3. **Add Sendable to actions**: Required for Swift 6
4. **Replace Effects with ActionTask**: Use `.run(id:)` pattern
5. **Update tests**: Use Store directly with Swift Testing's #expect
6. **Remove ViewStore**: Use Store directly with @State

## From Redux-like Architectures

### From ReSwift

**ReSwift:**
```swift
struct AppState: StateType {
    var count = 0
}

enum CounterAction: Action {
    case increment
}

func counterReducer(action: Action, state: AppState?) -> AppState {
    var state = state ?? AppState()
    switch action as? CounterAction {
    case .increment:
        state.count += 1
    }
    return state
}
```

**ViewFeature:**
```swift
struct CounterFeature: Feature {
    @Observable
    final class State {
        var count = 0
        init(count: Int = 0) { self.count = count }
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
```

**Key differences:**
- No global store - feature-scoped stores
- State is a class, not a struct
- Built-in async support via `ActionTask`
- Type-safe feature protocol

## From SwiftUI's @Observable ViewModels

### From ObservableObject

**Before: ObservableObject (Old Pattern)**
```swift
import SwiftUI
import Combine

class CounterViewModel: ObservableObject {
    @Published var count = 0

    func increment() {
        count += 1
    }

    func loadData() {
        Task {
            let data = try await api.fetch()
            await MainActor.run {  // Manual MainActor management
                self.data = data
            }
        }
    }
}

// In SwiftUI
struct CounterView: View {
    @StateObject private var viewModel = CounterViewModel()

    var body: some View {
        Text("\(viewModel.count)")
        Button("Increment") {
            viewModel.increment()
        }
    }
}
```

**After: ViewFeature**
```swift
import ViewFeature

struct CounterFeature: Feature {
    @Observable
    final class State {
        var count = 0
        var data: [Item] = []
    }

    enum Action: Sendable {
        case increment
        case loadData
        case dataLoaded([Item])
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .increment:
                state.count += 1
                return .none

            case .loadData:
                return .run(id: "load") {
                    let data = try await api.fetch()
                    await store.send(.dataLoaded(data))  // Automatic MainActor
                }

            case .dataLoaded(let items):
                state.data = items
                return .none
            }
        }
    }
}

// In SwiftUI
struct CounterView: View {
    @State private var store = Store(
        initialState: CounterFeature.State(),
        feature: CounterFeature()
    )

    var body: some View {
        Text("\(store.state.count)")
        Button("Increment") {
            store.send(.increment)
        }
    }
}
```

### From @Observable ViewModels

**Before: @Observable ViewModel**
```swift
import SwiftUI
import Observation

@Observable
final class UserViewModel {
    var user: User?
    var isLoading = false
    var errorMessage: String?

    func loadUser() async {
        isLoading = true
        errorMessage = nil

        do {
            // Easy to forget MainActor management
            let user = try await apiClient.fetchUser()
            self.user = user  // ⚠️ Is this on MainActor?
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func refresh() async {
        await loadUser()
    }
}

// In SwiftUI
struct UserView: View {
    @State private var viewModel = UserViewModel()

    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView()
            } else if let user = viewModel.user {
                Text(user.name)
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundColor(.red)
            }
        }
        .task {
            await viewModel.loadUser()
        }
    }
}
```

**After: ViewFeature**
```swift
import ViewFeature

struct UserFeature: Feature {
    let apiClient: APIClient

    @Observable  // Automatically MainActor in Swift 6.2 ✨
    final class State {
        var user: User?
        var isLoading = false
        var errorMessage: String?
    }

    enum Action: Sendable {
        case loadUser
        case userLoaded(User)
        case refresh
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .loadUser, .refresh:
                state.isLoading = true
                state.errorMessage = nil
                return .run(id: "load-user") {
                    let user = try await apiClient.fetchUser()
                    await store.send(.userLoaded(user))  // ✅ Always safe
                }
                .catch { error, state in
                    state.errorMessage = error.localizedDescription
                    state.isLoading = false
                }

            case .userLoaded(let user):
                state.user = user
                state.isLoading = false
                return .none
            }
        }
    }
}

// In SwiftUI
struct UserView: View {
    @State private var store = Store(
        initialState: UserFeature.State(),
        feature: UserFeature(apiClient: .production)
    )

    var body: some View {
        VStack {
            if store.state.isLoading {
                ProgressView()
            } else if let user = store.state.user {
                Text(user.name)
            }

            if let error = store.state.errorMessage {
                Text(error).foregroundColor(.red)
            }
        }
        .task {
            await store.send(.loadUser).value
        }
    }
}
```

**Benefits over @Observable ViewModels:**
- **Explicit action types** - All state mutations are explicit and traceable
- **Built-in task management** - Automatic task ID tracking and cancellation
- **Comprehensive testing** - Test business logic without mocking UI
- **Predictable data flow** - Unidirectional flow prevents implicit mutations
- **Thread safety** - Compile-time guarantees via Swift 6.2's MainActor isolation
- **Middleware support** - Add logging, analytics, or validation without touching core logic
- **Team consistency** - Enforced patterns across the codebase

## Common Migration Challenges

### Challenge 1: State Must Be a Class

**Issue:** TCA and ReSwift use value types for state.

**Solution:** Convert to @Observable class:

```swift
// Before (struct)
struct State: Equatable {
    var count = 0
}

// After (class)
@Observable
final class State {
    var count = 0
    init(count: Int = 0) { self.count = count }
}
```

**For Equatable testing:**
```swift
@Observable
final class State: Equatable {
    var count = 0

    init(count: Int = 0) { self.count = count }

    static func == (lhs: State, rhs: State) -> Bool {
        lhs.count == rhs.count
    }
}
```

### Challenge 2: Task Cancellation

**Issue:** TCA uses `.cancellable(id:)`, ViewFeature uses explicit IDs.

**Solution:** Always provide task IDs:

```swift
// TCA
return .run { ... }
    .cancellable(id: CancelID.fetch)

// ViewFeature
return .run(id: "fetch") { ... }
```

### Challenge 3: Dependency Injection

**Issue:** TCA has `@Dependency` property wrapper.

**Solution:** Use initializer injection:

```swift
struct Feature: Feature {
    let apiClient: APIClient

    // Inject dependencies via initializer
    init(apiClient: APIClient = .live) {
        self.apiClient = apiClient
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            // Use self.apiClient
        }
    }
}

// In tests:
let feature = Feature(apiClient: .mock)
```

### Challenge 4: Store Scoping

**Issue:** TCA's automatic scope composition.

**Solution:** Manual forwarding or nested stores:

```swift
struct ParentFeature: Feature {
    @Observable
    final class State {
        var child = ChildFeature.State()
    }

    enum Action: Sendable {
        case child(ChildFeature.Action)
    }

    let childFeature: ChildFeature

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .child(let childAction):
                // Option 1: Create child store
                let childStore = Store(
                    initialState: state.child,
                    feature: childFeature
                )
                await childStore.send(childAction).value
                state.child = childStore.state
                return .none
            }
        }
    }
}
```

## Migration Checklist

- [ ] Convert State to @Observable class
- [ ] Add Sendable conformance to Actions
- [ ] Replace Effect with ActionTask
- [ ] Add task IDs for cancellable operations
- [ ] Update tests to use Store with Swift Testing
- [ ] Replace ViewStore with direct Store access
- [ ] Implement dependency injection via initializers
- [ ] Update SwiftUI views to use @State
- [ ] Add Equatable to State if needed for debugging
- [ ] Test migration incrementally

## Performance Considerations

ViewFeature offers better performance due to:

1. **@Observable**: More efficient than Combine's ObservableObject
2. **Direct state mutation**: No defensive copying like TCA
3. **MainActor isolation**: Simplified concurrency model
4. **Minimal dependencies**: Only swift-log required

## Getting Help

- Review <doc:GettingStarted> for basics
- See <doc:Architecture> for design details
- Check <doc:TestingGuide> for testing patterns
- Open issues at [GitHub](https://github.com/ViewFeature/ViewFeature/issues)

## See Also

- <doc:GettingStarted>
- <doc:Architecture>
- <doc:TestingGuide>
- ``Store``
- ``Feature``
