# Getting Started

Learn how to integrate ViewFeature into your SwiftUI application.

## Overview

This guide walks through installing ViewFeature and building your first feature with state management, actions, and side effects.

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

## Basic Example

### 1. Define Your Feature

Create a feature with State, Action, and business logic:

```swift
import ViewFeature

struct CounterFeature: StoreFeature {
    // State: Observable class for SwiftUI integration
    @Observable
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

## Async Operations

Handle side effects with async tasks:

```swift
struct DataFeature: StoreFeature {
    @Observable
    final class State {
        var isLoading = false
        var data: [String] = []
    }

    enum Action: Sendable {
        case loadData
        case dataLoaded([String])
    }

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .loadData:
                state.isLoading = true
                return .run(id: "load-data") {
                    let data = try await fetchData()
                    await store.send(.dataLoaded(data))
                }

            case .dataLoaded(let items):
                state.data = items
                state.isLoading = false
                return .none
            }
        }
    }
}
```

## Next Steps

- Learn about the <doc:Architecture>
- Explore <doc:TestingGuide> for comprehensive testing
- Review <doc:MigrationGuide> if coming from other frameworks

## See Also

- ``Store``
- ``StoreFeature``
- ``ActionHandler``
- ``ActionTask``
