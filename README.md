# ViewFeature

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/platforms-iOS%2018%20%7C%20macOS%2015%20%7C%20watchOS%2011%20%7C%20tvOS%2018-lightgrey.svg)
![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

A lightweight, type-safe state management library for Swift built with Swift 6 strict concurrency and SwiftUI @Observable integration.

## Key Features

- Swift 6 with async/await and strict concurrency
- Type-safe state management with compile-time guarantees
- Native SwiftUI @Observable integration
- Flexible testing supporting non-Equatable states
- Middleware support for cross-cutting concerns
- 100% test coverage (267 tests)

## Quick Start

### Installation

```swift
dependencies: [
  .package(url: "https://github.com/ViewFeature/ViewFeature.git", from: "0.1.0")
]
```

### Example

```swift
import ViewFeature
import SwiftUI

struct CounterFeature: StoreFeature {
  @Observable
  final class State {
    var count = 0
    init(count: Int = 0) { self.count = count }
  }

  enum Action: Sendable {
    case increment, decrement
  }

  func handle() -> ActionHandler<Action, State> {
    ActionHandler { action, state in
      switch action {
      case .increment: state.count += 1
      case .decrement: state.count -= 1
      }
      return .none
    }
  }
}

struct CounterView: View {
  @State private var store = Store(
    initialState: CounterFeature.State(),
    feature: CounterFeature()
  )

  var body: some View {
    VStack {
      Text("\(store.state.count)").font(.largeTitle)
      Button("−") { store.send(.decrement) }
      Button("+") { store.send(.increment) }
    }
  }
}
```

## Architecture

Unidirectional data flow:

```
View → Action → Store → ActionHandler → State → View
                   ↓
              StoreTask (side effects)
```

**Store**: Holds state, processes actions, manages tasks
**ActionHandler**: Transforms state based on actions
**StoreTask**: Represents async operations (`.run`, `.cancel`, `.none`)
**TaskManager**: Manages concurrent task lifecycle

## Advanced Usage

### Async Tasks with Cancellation

```swift
return .run(id: "download") {
  // Long-running async operation
  try await Task.sleep(for: .seconds(1))
}
.catch { error, state in
  state.errorMessage = error.localizedDescription
}

// Cancel the task
return .cancel(id: "download")
```

### Middleware

Add cross-cutting concerns like logging or analytics:

```swift
func handle() -> ActionHandler<Action, State> {
  ActionHandler { action, state in
    // Handle actions
  }
  .use(LoggingMiddleware(category: "MyFeature"))
  .use(AnalyticsMiddleware())
}
```

## 🧪 Testing

ViewFeature provides comprehensive testing utilities using Swift Testing framework with flexible assertion patterns:

### TestStore - Three Testing Patterns

TestStore supports both Equatable and non-Equatable states with three assertion patterns:

#### Pattern 1: Full State Comparison (Equatable Required)
```swift
import Testing
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
@Suite struct CounterTests {
  @Test func increment() async {
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
@Suite struct FlexibleTests {
  @Test func complexState() async {
    let store = TestStore(
      initialState: AppFeature.State(),  // Non-Equatable state OK!
      feature: AppFeature()
    )

    // Custom assertions - test only what matters
    await store.send(.loadUser, assert: { state in
      #expect(state.user?.name == "Alice")
      #expect(state.isLoading)
      #expect(!state.metadata.isEmpty)
    })
  }
}
```

#### Pattern 3: KeyPath Assertions (Most Concise)
```swift
@MainActor
@Suite struct KeyPathTests {
  @Test func singleProperty() async {
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
@Suite struct IntegrationTests {
  @Test func realStore() async {
    let store = Store(
      initialState: CounterFeature.State(),
      feature: CounterFeature()
    )

    // Wait for action to complete
    await store.send(.increment).value

    // Verify state
    #expect(store.state.count == 1)
  }

  @Test func asyncTaskCompletion() async {
    let store = Store(
      initialState: DataFeature.State(),
      feature: DataFeature()
    )

    // Store.send() waits for background tasks to complete
    await store.send(.loadData).value

    // Task is guaranteed to be complete - no Task.sleep needed!
    #expect(!store.state.isLoading)
    #expect(store.runningTaskCount == 0)
  }
}
```

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
