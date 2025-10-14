# ``ViewFeature``

Modern state management for Swift 6.2 with async/await, automatic MainActor isolation, and SwiftUI integration.

## Overview

ViewFeature is a type-safe state management library built with Swift 6.2 and strict concurrency, designed for seamless SwiftUI integration. It provides a unidirectional data flow architecture inspired by Redux and The Composable Architecture, reimagined for modern Swift.

### Why ViewFeature?

**Built for Swift 6.2's Reality**

Swift and SwiftUI have evolved significantly. ViewFeature embraces these modern features:

- **Swift 6.2** brings default MainActor isolation for @Observable
- **@Observable** provides efficient, native SwiftUI observation
- **async/await** is the standard for async operations
- **Strict concurrency** eliminates data races at compile time

Traditional Redux-style libraries were designed before these features existed. ViewFeature learns from their architectural principles but is rebuilt from scratch for Swift 6.2 and SwiftUI's reality.

### Key Features

- 🎯 **Modern Swift**: Built with Swift 6.2, async/await, and strict concurrency
- 🛡️ **Thread-Safe by Default**: Automatic MainActor isolation for `@Observable` state
- ⚡ **Type-Safe**: Leverages Swift's type system for compile-time safety
- 🔄 **Reactive**: Seamless SwiftUI integration with @Observable
- 🏗 **SOLID Architecture**: Clean separation of concerns following SOLID principles
- 🧪 **Flexible Testing**: 3 testing patterns supporting both Equatable and non-Equatable states
- ✅ **100% Tested**: 267 tests with comprehensive coverage
- 📦 **Lightweight**: Minimal dependencies (only swift-log)
- 🚀 **Production-Ready**: Battle-tested integration and performance tests

### Thread Safety by Default

In Swift 6.2, `@Observable` classes are automatically MainActor-isolated, which means:

```swift
struct CounterFeature: Feature {
    @Observable  // Automatically MainActor in Swift 6.2 ✨
    final class State {
        var count = 0  // Always accessed on main thread
        // No @MainActor annotation needed!
    }

    enum Action: Sendable {
        case increment
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .increment:
                state.count += 1  // ✅ Always safe on MainActor
                return .none
            }
        }
    }
}
```

### Natural SwiftUI Integration

```swift
struct CounterView: View {
    @State private var store = Store(
        initialState: CounterFeature.State(),
        feature: CounterFeature()
    )

    var body: some View {
        VStack {
            // ✅ No isolation warnings - View and State are both MainActor
            Text("\(store.state.count)")
            Button("+") { store.send(.increment) }
        }
    }
}
```

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

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Architecture>
- ``Store``
- ``Feature``

### Action Handling

- ``ActionHandler``
- ``ActionProcessor``
- ``ActionTask``

### Testing

- <doc:TestingGuide>

### Middleware

- ``ActionMiddleware``
- ``LoggingMiddleware``
- ``MiddlewareManager``

### Task Management

- ``TaskManager``
- ``StoreTask``

### Migration

- <doc:MigrationGuide>

### Best Practices

- <doc:BestPractices>
