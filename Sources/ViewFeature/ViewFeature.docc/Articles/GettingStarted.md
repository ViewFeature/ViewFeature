# Getting Started

Learn how to integrate ViewFeature into your SwiftUI application with Swift 6.2.

## Overview

This guide walks through installing ViewFeature and building your first feature with state management, actions, and side effects. You'll learn how Swift 6.2's automatic MainActor isolation makes thread-safe state management effortless.

## Requirements

- iOS 18.0+ / macOS 15.0+ / watchOS 11.0+ / tvOS 18.0+
- **Swift 6.2+** ⚠️
- Xcode 16.0+

> Important: ViewFeature relies on Swift 6.2's **default MainActor isolation** for `@Observable` classes. This provides automatic thread safety without manual `@MainActor` annotations.

## Installation

### Swift Package Manager

Add ViewFeature to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ViewFeature/ViewFeature.git", from: "0.1.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/ViewFeature/ViewFeature.git`
3. Select version: 0.1.0 or later

## Your First Feature

### 1. Define Your Feature

Create a feature with State, Action, and business logic:

```swift
import ViewFeature

struct CounterFeature: Feature {
    // State: Observable class for SwiftUI integration
    @Observable  // Automatically MainActor in Swift 6.2 ✨
    final class State {
        var count = 0

        init(count: Int = 0) {
            self.count = count
        }
    }

    // Actions: Events that trigger state changes
    enum Action: Sendable {
        case increment
        case decrement
        case reset
    }

    // Handler: Business logic
    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .increment:
                state.count += 1  // ✅ Always safe on MainActor
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

> Note: In Swift 6.2, `@Observable` classes are automatically MainActor-isolated. No need for explicit `@MainActor` annotations!

### 2. Use in SwiftUI

Integrate the store into your view:

```swift
import SwiftUI
import ViewFeature

struct CounterView: View {
    @State private var store = Store(
        initialState: CounterFeature.State(),
        feature: CounterFeature()
    )

    var body: some View {
        VStack(spacing: 20) {
            Text("\(store.state.count)")
                .font(.largeTitle)

            HStack {
                Button("−") { store.send(.decrement) }
                Button("Reset") { store.send(.reset) }
                Button("+") { store.send(.increment) }
            }
        }
    }
}
```

That's it! You now have:
- ✅ Thread-safe state management
- ✅ Compile-time safety
- ✅ Automatic SwiftUI updates
- ✅ Testable business logic

## Async Operations

Handle side effects with async tasks:

```swift
struct DataFeature: Feature {
    let apiClient: APIClient

    @Observable
    final class State {
        var isLoading = false
        var data: [String] = []
        var errorMessage: String?
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
                state.errorMessage = nil
                return .run(id: "load-data") {
                    let data = try await apiClient.fetch()
                    await store.send(.dataLoaded(data))
                }
                .catch { error, state in
                    state.errorMessage = error.localizedDescription
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
```

### Using in SwiftUI

```swift
struct DataView: View {
    @State private var store = Store(
        initialState: DataFeature.State(),
        feature: DataFeature(apiClient: .production)
    )

    var body: some View {
        VStack {
            if store.state.isLoading {
                ProgressView()
            } else {
                List(store.state.data, id: \.self) { item in
                    Text(item)
                }
            }

            if let error = store.state.errorMessage {
                Text(error).foregroundColor(.red)
            }
        }
        .toolbar {
            Button("Load") {
                store.send(.loadData)
            }
        }
        .task {
            // Load data when view appears
            await store.send(.loadData).value
        }
    }
}
```

## Thread Safety Explained

### Automatic MainActor Isolation

In Swift 6.2, `@Observable` classes are automatically MainActor-isolated:

```swift
@Observable  // This class is MainActor by default
final class State {
    var count = 0  // Always accessed on main thread
}

// This won't compile - caught at build time!
Task.detached {
    store.state.count += 1  // ❌ Error: state is MainActor-isolated
}

// Correct way - explicit isolation
Task.detached {
    await store.send(.increment)  // ✅ Properly isolated
}
```

### Background Work is Still Possible

Actions run on MainActor, but effects can spawn background work:

```swift
case .processImage:
    return .run(id: "process") {
        // This closure can do background work
        let processed = await heavyImageProcessing()  // Off main thread

        // Send results back to MainActor
        await store.send(.imageProcessed(processed))  // Automatically MainActor
    }
```

## Dependency Injection

Always inject dependencies for testability:

```swift
protocol APIClient: Sendable {
    func fetch() async throws -> [String]
}

struct ProductionAPIClient: APIClient {
    func fetch() async throws -> [String] {
        // Real API call
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([String].self, from: data)
    }
}

struct Feature: Feature {
    let apiClient: APIClient

    // Default to production, but allow injection
    init(apiClient: APIClient = ProductionAPIClient()) {
        self.apiClient = apiClient
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            // Use self.apiClient
        }
    }
}

// In production
let store = Store(
    initialState: Feature.State(),
    feature: Feature()  // Uses production client
)

// In tests
let store = Store(
    initialState: Feature.State(),
    feature: Feature(apiClient: MockAPIClient())  // Uses mock
)
```

## Next Steps

- Learn about the <doc:Architecture> and how data flows
- Explore <doc:TestingGuide> for comprehensive testing strategies
- Review <doc:MigrationGuide> if coming from other frameworks
- Check out <doc:BestPractices> for recommended patterns

## See Also

- ``Store``
- ``Feature``
- ``ActionHandler``
- ``ActionTask``
