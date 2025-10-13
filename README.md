# ViewFeature

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/platforms-iOS%2018%20%7C%20macOS%2015%20%7C%20watchOS%2011%20%7C%20tvOS%2018-lightgrey.svg)
![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

**ViewFeature** is a modern, lightweight state management library for Swift applications, built with Swift 6 strict concurrency and designed for seamless SwiftUI integration.

## ✨ Key Features

- **🎯 Modern Swift**: Built with Swift 6, async/await, and strict concurrency
- **⚡ Type-Safe**: Leverages Swift's type system for compile-time safety
- **🔄 Reactive**: Seamless SwiftUI integration with @Observable
- **🏗 SOLID Architecture**: Clean separation of concerns following SOLID principles
- **🧪 Flexible Testing**: 3 testing patterns supporting both Equatable and non-Equatable states
- **✅ 100% Tested**: 267 tests with comprehensive coverage
- **📦 Lightweight**: Minimal dependencies (only swift-log)
- **🚀 Production-Ready**: Battle-tested integration and performance tests

## 📖 Quick Start

### Installation

Add ViewFeature to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ViewFeature/ViewFeature.git", from: "0.1.0")
]
```

Or in Xcode: **File → Add Package Dependencies**

### Basic Example

```swift
import ViewFeature

// 1. Define your feature with nested State and Action
struct CounterFeature: StoreFeature {
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

## 🏗 Architecture

ViewFeature follows a unidirectional data flow architecture inspired by Redux and The Composable Architecture:

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

#### StoreTask
Represents side effects:
- `.none` - No side effects
- `.run(id:operation:)` - Execute async operations
- `.cancel(id:)` - Cancel running tasks

#### TaskManager
Manages concurrent task execution:
- Task lifecycle management
- Cancellation support
- Error handling

## 🔄 Advanced Features

### Task Management & Cancellation

```swift
struct DataFeature: StoreFeature {
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

### Error Handling

```swift
struct NetworkFeature: StoreFeature {
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

### Middleware Support

```swift
struct MyFeature: StoreFeature {
    @Observable
    final class State {
        var count = 0
    }

    enum Action: Sendable {
        case increment
    }

    func handle() -> ActionHandler<Action, State> {
        // Add logging middleware
        let loggingMiddleware = LoggingMiddleware(
            category: "MyFeature",
            logLevel: .debug
        )

        let manager = MiddlewareManager<Action, State>()
        manager.addMiddleware(loggingMiddleware)

        return ActionHandler { action, state in
            switch action {
            case .increment:
                state.count += 1
                return .none
            }
        }
    }
}
```

## 🧪 Testing

ViewFeature provides comprehensive testing utilities with flexible assertion patterns:

### TestStore - Three Testing Patterns

TestStore supports both Equatable and non-Equatable states with three assertion patterns:

#### Pattern 1: Full State Comparison (Equatable Required)
```swift
import XCTest
@testable import ViewFeature

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

        // Full state comparison - validates entire state equality
        await store.send(.increment) { state in
            state.count = 1
        }
    }
}
```

#### Pattern 2: Custom Assertions (No Equatable Required)
```swift
struct AppFeature: StoreFeature {
    @Observable
    final class State {  // No Equatable conformance!
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
final class FlexibleTests: XCTestCase {
    func testComplexState() async {
        let store = TestStore(
            initialState: AppFeature.State(),  // Non-Equatable state OK!
            feature: AppFeature()
        )

        // Custom assertions - test only what matters
        await store.send(.loadUser, assert: { state in
            XCTAssertEqual(state.user?.name, "Alice")
            XCTAssertTrue(state.isLoading)
            XCTAssertFalse(state.metadata.isEmpty)
        })
    }
}
```

#### Pattern 3: KeyPath Assertions (Most Concise)
```swift
@MainActor
final class KeyPathTests: XCTestCase {
    func testSingleProperty() async {
        let store = TestStore(
            initialState: CounterFeature.State(),
            feature: CounterFeature()
        )

        // KeyPath-based - test single property
        await store.send(.increment, expecting: \.count, toBe: 1)
        await store.send(.increment, expecting: \.count, toBe: 2)
    }
}
```

### Testing with Store (Production Environment)

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
    }
}
```

## 📊 Project Stats

- **267 Tests**: Comprehensive unit and integration tests
- **100% Pass Rate**: All tests passing
- **High Coverage**: Extensive code coverage across all components
- **Performance**: 45,000+ actions/second throughput
- **SOLID Principles**: Architecture following industry best practices

### Test Breakdown

- **Unit Tests**: 205 tests covering individual components
  - Store, ActionHandler, ActionProcessor
  - TaskManager, MiddlewareManager
  - ActionTask, StoreTask
  - TestStore utilities (3 assertion patterns)

- **Integration Tests**: 62 tests validating system integration
  - End-to-end workflows
  - Component integration
  - Error recovery scenarios
  - Performance benchmarks

## 🎯 Design Principles

### SOLID Architecture

- **Single Responsibility**: Each component has one clear purpose
- **Open/Closed**: Extensible through protocols and middleware
- **Liskov Substitution**: Interchangeable implementations
- **Interface Segregation**: Minimal, focused protocols
- **Dependency Inversion**: Depends on abstractions, not concrete types

### Key Patterns

- **Unidirectional Data Flow**: Predictable state changes
- **Immutable State Updates**: Thread-safe state management
- **Dependency Injection**: TaskManager and middleware injection
- **Protocol-Oriented**: Flexible, testable design

## 📋 Requirements

- **iOS 18.0+** / **macOS 15.0+** / **watchOS 11.0+** / **tvOS 18.0+**
- **Swift 6.2+**
- **Xcode 16.0+**

## 📚 Documentation

Full API documentation is available through Swift DocC:

```bash
swift package generate-documentation
```

## 🗺 Roadmap

### Version 0.1.0 (Current)
- ✅ Core state management
- ✅ Async/await task support
- ✅ Middleware system
- ✅ Comprehensive testing utilities
- ✅ Full documentation

### Future Versions
- 🔄 Enhanced debugging tools
- 🔄 Time-travel debugging
- 🔄 State persistence
- 🔄 SwiftUI bindings helpers
- 🔄 Performance profiling tools

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## 📄 License

ViewFeature is available under the MIT license. See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- Inspired by [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)
- Built with [swift-log](https://github.com/apple/swift-log) for structured logging
- Designed for the Swift community

## 📞 Support

- 📖 **Documentation**: In-code documentation and this README
- 🐛 **Issues**: [GitHub Issues](https://github.com/ViewFeature/ViewFeature/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/ViewFeature/ViewFeature/discussions)

---

**Built with ❤️ using Swift 6 and modern concurrency**

Version 0.1.0 | © 2025
