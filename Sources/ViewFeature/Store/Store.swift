import Foundation
import Logging
import Observation

/// The main store for managing application state and dispatching actions.
///
/// `Store` provides a Redux-like unidirectional data flow architecture for SwiftUI apps.
/// It coordinates between state management, action processing, and task execution while
/// maintaining the Single Responsibility Principle by delegating to specialized components.
///
/// ## Example Usage
/// ```swift
/// struct AppFeature: Feature {
///     @Observable
///     final class State {
///         var count: Int = 0
///
///         init(count: Int = 0) {
///             self.count = count
///         }
///     }
///
///     enum Action: Sendable {
///         case increment
///         case decrement
///     }
///
///     func handle() -> ActionHandler<Action, State> {
///         ActionHandler { action, state in
///             switch action {
///             case .increment:
///                 state.count += 1
///             case .decrement:
///                 state.count -= 1
///             }
///             return .none
///         }
///     }
/// }
///
/// // Use in SwiftUI with @State
/// struct ContentView: View {
///     @State private var store = Store(
///         initialState: AppFeature.State(),
///         feature: AppFeature()
///     )
///
///     var body: some View {
///         VStack {
///             Text("Count: \(store.state.count)")
///             Button("Increment") {
///                 store.send(.increment)
///             }
///         }
///     }
/// }
/// ```
///
/// - Important: Always use `@State` to hold the Store in SwiftUI Views to maintain
///   the store instance across view updates and prevent unnecessary re-initialization.
///
/// ## Topics
/// ### Creating a Store
/// - ``init(initialState:feature:taskManager:)``
///
/// ### Accessing State
/// - ``state``
///
/// ### Dispatching Actions
/// - ``send(_:)``
///
/// ### Task Inspection
/// - ``runningTaskCount``
/// - ``isTaskRunning(id:)``
@Observable
@MainActor
public final class Store<F: Feature> {
  private var _state: F.State
  private let taskManager: TaskManager
  private let handler: ActionHandler<F.Action, F.State>
  private let feature: F
  private let logger: Logger

  /// The current state of the feature.
  ///
  /// The Store is @Observable, so accessing this property from SwiftUI views enables
  /// automatic updates when state changes. Access this property from your views to
  /// read the current state.
  public var state: F.State {
    _state
  }

  // MARK: - Initialization

  /// Primary initializer with full DIP compliance
  public init(
    initialState: F.State,
    feature: F,
    taskManager: TaskManager = TaskManager()
  ) {
    self.feature = feature
    self._state = initialState
    self.taskManager = taskManager
    self.handler = feature.handle()

    let subsystem = Bundle.main.bundleIdentifier ?? "com.viewfeature.library"
    let featureName = String(describing: F.self)
    self.logger = Logger(label: "\(subsystem).Store.\(featureName)")
  }

  // MARK: - Action Dispatch API

  /// Dispatches an action and processes it through the handler
  ///
  /// - Parameter action: The action to dispatch
  /// - Returns: A Task that completes when the action processing finishes.
  ///   You can await this task if you need to ensure the action is fully processed.
  ///
  /// ## Example
  /// ```swift
  /// // Fire and forget
  /// store.send(.increment)
  ///
  /// // Wait for completion
  /// await store.send(.loadData).value
  /// ```
  ///
  /// ## Important: Sequential Execution Behavior
  /// Actions are processed **sequentially** on the MainActor. If an action returns
  /// a `.run` task, the Store will await its completion before processing the next action.
  ///
  /// This means:
  /// ```swift
  /// store.send(.longRunningTask)  // Takes 5 seconds
  /// store.send(.quickTask)        // Will wait until longRunningTask completes
  /// ```
  ///
  /// **Why this design?**
  /// - Ensures state consistency (no concurrent mutations)
  /// - Simplifies reasoning about action order
  /// - Prevents race conditions
  ///
  /// **Note:** Even with task IDs, the Store awaits task completion in `executeTask`.
  /// This is intentional to maintain state consistency and simplify the mental model.
  ///
  /// If you need truly concurrent background work, dispatch it inside the `.run` block
  /// without making the outer operation wait:
  /// ```swift
  /// return .run { state in
  ///   // Fire-and-forget background work
  ///   Task.detached {
  ///     await heavyBackgroundWork()
  ///   }
  ///   // This returns immediately
  /// }
  /// ```
  @discardableResult
  public func send(_ action: F.Action) -> Task<Void, Never> {
    Task { @MainActor in
      await self.processAction(action)
    }
  }

  // MARK: - Private Implementation

  private func processAction(_ action: F.Action) async {
    // State is a reference type (AnyObject), so handler mutations affect _state directly
    var mutableState = _state
    let actionTask = await handler.handle(action: action, state: &mutableState)
    // No reassignment needed - _state and mutableState reference the same object
    await executeTask(actionTask.storeTask)
  }

  private func executeTask(_ storeTask: StoreTask<F.Action, F.State>) async {
    switch storeTask {
    case .none:
      break

    case .run(let id, let operation, let onError):
      // Cancel existing task with same ID before starting new one
      taskManager.cancelTaskInternal(id: id)

      // Pass operation directly to TaskManager
      // TaskManager will create and track the Task
      let task = taskManager.executeTask(
        id: id,
        operation: { @MainActor [weak self] in
          guard let self else { return }
          try await operation(self._state)
        },
        onError: onError.map { handler in
          { @MainActor [weak self] (error: Error) in
            guard let self else { return }
            handler(error, self._state)
          }
        }
      )

      await task.value

    case .cancel(let id):
      taskManager.cancelTaskInternal(id: id)
    }
  }

  // MARK: - Task Inspection API

  /// Returns the number of currently running tasks.
  ///
  /// Use this property to monitor task activity for debugging or UI purposes.
  ///
  /// ## Example
  /// ```swift
  /// Text("Active tasks: \(store.runningTaskCount)")
  /// ```
  public var runningTaskCount: Int {
    taskManager.runningTaskCount
  }

  /// Checks if a specific task is currently running.
  ///
  /// Use this method to query task status for UI updates or conditional logic.
  ///
  /// ## Example
  /// ```swift
  /// if store.isTaskRunning(id: "download") {
  ///   ProgressView()
  /// }
  /// ```
  ///
  /// - Parameter id: The task identifier to check
  /// - Returns: `true` if the task is currently running, `false` otherwise
  public func isTaskRunning<ID: TaskID>(id: ID) -> Bool {
    taskManager.isTaskRunning(id: id)
  }
}
