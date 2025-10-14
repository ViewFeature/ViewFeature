# Design Decisions

Understanding ViewFeature's intentional design choices.

## Overview

ViewFeature makes specific architectural choices that differentiate it from other state management libraries. These decisions are intentional trade-offs aligned with Swift 6.2's concurrency model and SwiftUI's architecture.

## No State Composition (No `Scope`)

ViewFeature **intentionally does not** provide state composition mechanisms like TCA's `Scope`, `ifLet`, or `forEach`. Instead, state hierarchies are managed through SwiftUI's view hierarchy using `@State`.

### Rationale

**Alignment with MainActor + Sequential Execution**

ViewFeature's core design principle is:
- All stores operate on `MainActor`
- All actions process sequentially
- No concurrent state mutations possible

Under these constraints, the complex state composition machinery found in other libraries becomes unnecessary:

```swift
// ViewFeature approach - Simple and direct
struct ParentView: View {
    @State private var parentStore = Store(
        initialState: ParentFeature.State(),
        feature: ParentFeature()
    )
    @State private var childStore = Store(
        initialState: ChildFeature.State(),
        feature: ChildFeature()
    )
    
    var body: some View {
        VStack {
            ParentContent(store: parentStore)
            ChildView(store: childStore)
        }
    }
}
```

### Benefits

- **Simplicity**: Zero boilerplate for parent-child relationships
- **Natural Lifecycle**: Store lifecycle matches View lifecycle automatically
- **SwiftUI Native**: Uses SwiftUI's built-in `@State` management
- **No Magic**: Explicit dependencies, no hidden routing

### Trade-offs

**When This Works Well:**
- Apps with shallow view hierarchies (2-4 levels)
- Independent features with minimal cross-communication
- Small to medium apps (5-50 screens)

**When You Might Need Alternatives:**
- Deep state hierarchies (10+ levels)
- Complex state dependencies between distant components
- Centralized state serialization requirements

**Parent-Child Communication:**

Communication requires explicit wiring:

```swift
struct ParentView: View {
    @State private var parentStore = Store(...)
    @State private var childStore = Store(...)
    
    var body: some View {
        ChildView(
            store: childStore,
            onUpdate: { value in
                parentStore.send(.childDidUpdate(value))
            }
        )
    }
}
```

## Sequential Action Processing

Actions are processed **sequentially** on the MainActor. When an action returns a `.run` task, the Store awaits its completion before processing the next action.

### Rationale

**Follows Apple's Swift 6.2 Philosophy**

Swift 6.2 introduces default `MainActor` isolation for `@Observable` classes. ViewFeature embraces this philosophy:

```swift
// Swift 6.2 - @Observable is automatically MainActor
@Observable
final class State {
    var count = 0  // MainActor-isolated by default
}
```

**Sequential execution ensures:**
1. **State Consistency**: No concurrent mutations, ever
2. **Predictability**: Actions execute in dispatch order
3. **Simplicity**: No need to reason about concurrent state access
4. **Compile-Time Safety**: Data races caught at compile time

### Implementation

```swift
public func send(_ action: F.Action) -> Task<Void, Never> {
    Task { @MainActor in
        await self.processAction(action)  // Sequential
    }
}

private func processAction(_ action: F.Action) async {
    // Process action
    let task = await handler.handle(action: action, state: &state)
    // Wait for task completion before returning
    await executeTask(task)  // Blocks until complete
}
```

### Benefits

- **Zero Race Conditions**: Impossible by design
- **Predictable Execution**: Actions always execute in order
- **Simplified Mental Model**: No need to think about concurrency
- **Alignment with Platform**: Follows Swift 6.2 conventions

### Trade-offs

**Potential UI Blocking:**

Long-running tasks block subsequent actions:

```swift
store.send(.heavyTask)  // Takes 5 seconds
store.send(.uiUpdate)   // Waits 5 seconds
```

**Solution: Explicit Concurrency**

For truly independent background work, use `Task.detached`:

```swift
return .run { state in
    Task.detached {
        // Heavy computation off main thread
        await performComputation()
    }
    // Returns immediately - doesn't block
}
```

### Best Practices

1. **Keep `.run` operations quick** (< 1 second ideal)
2. **Use `Task.detached`** for heavy background work
3. **Dispatch to background queues** explicitly when needed
4. **Design actions to be atomic** operations

## Comparison with TCA

| Aspect | ViewFeature | The Composable Architecture |
|--------|-------------|----------------------------|
| State Composition | ❌ None - View-driven | ✅ `Scope`, `ifLet`, `forEach` |
| Execution Model | Sequential | Concurrent (with Combine) |
| State Type | `@Observable class` | `struct` (value semantics) |
| Effects | async/await `.run` | `Effect<Action>` publisher |
| Complexity | Low - Simple API | High - Powerful but complex |
| Use Case | Small/Medium apps | Large apps with complex state |

## When to Use ViewFeature

**✅ Ideal For:**
- Swift 6.2+ projects
- Apps with straightforward state hierarchies
- Teams preferring simplicity over power
- Projects where SwiftUI's view tree naturally represents state relationships

**⚠️ Consider Alternatives When:**
- Managing very deep state hierarchies (10+ levels)
- Need sophisticated state composition
- Require state serialization/time-travel debugging at scale
- Building large-scale apps with complex domain models

## See Also

- ``Store``
- ``Feature``
- <doc:GettingStarted>
