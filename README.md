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
- Simple and straightforward testing with Swift Testing
- Middleware support for cross-cutting concerns
- Comprehensive test coverage (258 tests)

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

struct CounterFeature: Feature {
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

### Async Tasks with Error Handling

```swift
// Simple async task
return .run { state in
  let data = try await api.fetch()
  state.data = data
}

// With error handling
return .run(id: "download") { state in
  let file = try await downloader.download(url)
  state.downloadedFile = file
}
.catch { error, state in
  state.errorMessage = error.localizedDescription
  state.isDownloading = false
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

## Testing

ViewFeature uses standard Swift Testing framework with direct Store testing:

```swift
import Testing
@testable import ViewFeature

@MainActor
@Test func counterIncrement() async {
  // GIVEN: Initial state
  let store = Store(
    initialState: CounterFeature.State(count: 0),
    feature: CounterFeature()
  )

  // WHEN: Increment action is sent
  await store.send(.increment).value

  // THEN: Count should increase
  #expect(store.state.count == 1)
}

@Test func asyncDataLoading() async {
  let store = Store(
    initialState: DataFeature.State(),
    feature: DataFeature()
  )

  // Send action and wait for completion
  await store.send(.loadData).value

  // Verify state after async operation
  #expect(store.state.data != nil)
  #expect(!store.state.isLoading)
}

@Test func taskCancellation() async {
  let store = Store(
    initialState: DownloadFeature.State(),
    feature: DownloadFeature()
  )

  // Start download
  store.send(.startDownload)

  // Cancel it
  await store.send(.cancelDownload).value

  // Verify cancellation
  #expect(!store.isTaskRunning(id: "download"))
}
```

## Requirements

- iOS 18.0+ / macOS 15.0+ / watchOS 11.0+ / tvOS 18.0+
- Swift 6.2+
- Xcode 16.0+

## Documentation

Generate API documentation:
```bash
swift package generate-documentation
```

## License

MIT License. See [LICENSE](LICENSE) for details.

Inspired by [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)
