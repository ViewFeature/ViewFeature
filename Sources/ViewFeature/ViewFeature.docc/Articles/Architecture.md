# Architecture

Understanding ViewFeature's unidirectional data flow architecture.

## Overview

ViewFeature implements a unidirectional data flow pattern inspired by Redux and The Composable Architecture, providing predictable state management with clear separation of concerns.

## Data Flow

```
┌─────────────┐    Action     ┌──────────────┐
│    View     │──────────────▶│    Store     │
│  (SwiftUI)  │               │              │
└─────────────┘               └──────────────┘
       ▲                             │
       │                             ▼
       │                      ┌──────────────┐
       │        State         │ActionHandler │
       └──────────────────────│   (Feature)  │
                              └──────────────┘
                                     │
                              ┌──────▼──────┐
                              │ StoreTask   │
                              │(Side Effects)│
                              └─────────────┘
```

### Flow Sequence

1. **User Interaction** → View dispatches an Action
2. **Action Processing** → ActionHandler receives Action and current State
3. **State Mutation** → Handler modifies State directly (inout parameter)
4. **Side Effects** → Handler returns ActionTask for async operations
5. **State Observation** → SwiftUI observes State changes via @Observable
6. **View Update** → View automatically re-renders

## Core Components

### Store

The central coordinator managing the application state lifecycle.

**Responsibilities:**
- Holds current state
- Dispatches actions to ActionHandler
- Executes side effects via TaskManager
- Provides @Observable state for SwiftUI

**Key Design:**
```swift
@Observable
public final class Store<Feature: StoreFeature> {
    private var _state: Feature.State
    private let taskManager: TaskManager
    private let handler: ActionHandler<Feature.Action, Feature.State>

    public var state: Feature.State { _state }

    public func send(_ action: Feature.Action) -> Task<Void, Never>
}
```

**MainActor Isolation:**
All state mutations occur on MainActor, ensuring thread-safety and SwiftUI compatibility.

### StoreFeature

Protocol defining a feature's structure and behavior.

**Contract:**
- `State`: @Observable class holding feature state
- `Action`: Sendable enum describing events
- `handle()`: Returns ActionHandler with business logic

**Benefits:**
- Modular: Features are self-contained units
- Testable: Clear input/output boundaries
- Composable: Features can be nested or combined

### ActionHandler

Processes actions and produces state changes and side effects.

**Processing Model:**
```swift
ActionHandler { action, state in  // state is inout
    switch action {
    case .increment:
        state.count += 1  // Direct mutation
        return .none    // No side effects

    case .loadData:
        state.isLoading = true
        return .run(id: "load") {  // Async side effect
            let data = try await api.fetch()
            await store.send(.dataLoaded(data))
        }
    }
}
```

**State Mutation:**
- Direct mutation via `inout` parameter
- No reducer-style copying
- Optimal performance with @Observable

### ActionTask

Represents side effects returned from action processing.

**Types:**
- `.none`: Synchronous state-only changes
- `.run(id:operation:)`: Async operations with unique ID
- `.cancel(id:)`: Cancel running task by ID

**Task Management:**
```swift
return .run(id: "fetch") {
    try await performNetworkRequest()
}

// Later, cancel if needed:
return .cancel(id: "fetch")
```

### TaskManager

Manages concurrent task execution and lifecycle.

**Features:**
- Task registration with unique IDs
- Automatic cleanup on completion
- Cancellation support
- Error handling

**Isolation:**
Operates on MainActor, synchronizing with state mutations.

## Concurrency Model

### MainActor Default Isolation

ViewFeature uses `.defaultIsolation(MainActor.self)` in Package.swift, ensuring:
- All code runs on MainActor by default
- No data races with SwiftUI
- Simplified concurrency model

### @Observable Integration

State classes use @Observable:
- No manual @MainActor annotations needed
- SwiftUI automatically tracks dependencies
- Efficient change propagation

### Task Execution

Side effects run on MainActor:
- Can dispatch actions without isolation concerns
- Errors handled within MainActor context
- Cancellation is immediate and safe

## SOLID Principles

### Single Responsibility

- **Store**: State management
- **ActionHandler**: Business logic
- **TaskManager**: Async task lifecycle
- **Middleware**: Cross-cutting concerns

### Open/Closed

Extensible via:
- Custom middleware
- Protocol-oriented design
- Generic constraints

### Liskov Substitution

Protocols enable interchangeable implementations:
- Multiple middleware implementations
- Test doubles via protocols
- Dependency injection

### Interface Segregation

Focused protocols:
- `StoreFeature`: Minimal contract
- `Middleware`: Specific hooks only
- `AssertionProvider`: Testing abstraction

### Dependency Inversion

Depends on abstractions:
- TaskManager injected into Store
- Middleware registered dynamically
- Protocol-based boundaries

## Performance Considerations

### State Updates

**Direct Mutation:**
```swift
state.count += 1  // ✅ Efficient
```

**Not:**
```swift
return State(count: state.count + 1)  // ❌ Unnecessary copying
```

### Observable Efficiency

The @Observable macro provides:
- Fine-grained change tracking
- Minimal re-renders
- No manual change notifications

### Task Management

- Tasks auto-cleanup on completion
- ID-based cancellation is O(1)
- No memory leaks from long-running tasks

## Best Practices

### Feature Design

1. **Keep features focused** - One domain per feature
2. **Nest State and Action** - Better namespacing
3. **Use descriptive actions** - `userTappedLoginButton` not `action1`
4. **Handle errors gracefully** - Use `.onError` handler

### State Management

1. **Observable classes only** - SwiftUI requirement
2. **Equatable optional** - Enables TestStore full assertions
3. **Avoid computed properties** - Store derived data if expensive

### Side Effects

1. **Always use task IDs** - Enables cancellation
2. **Dispatch completion actions** - Keep state in sync
3. **Handle errors in handler** - Don't crash on network failures

### Testing

1. **Test state changes** - Use TestStore patterns
2. **Mock side effects** - Inject dependencies
3. **Verify action sequences** - Check `actionHistory`

## See Also

- ``Store``
- ``StoreFeature``
- ``ActionHandler``
- ``TaskManager``
- <doc:TestingGuide>
