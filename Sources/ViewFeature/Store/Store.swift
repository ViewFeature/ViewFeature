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
/// struct AppFeature: StoreFeature {
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
/// ### Task Management
/// - ``cancelTask(id:)``
/// - ``cancelAllTasks()``
/// - ``runningTaskCount``
/// - ``isTaskRunning(id:)``
@Observable
public final class Store<Feature: StoreFeature> {
  private var _state: Feature.State
  private let taskManager: TaskManager
  private let handler: ActionHandler<Feature.Action, Feature.State>
  private let feature: Feature
  private let logger: Logger

  /// Exposes the current state
  public var state: Feature.State {
    _state
  }

  // MARK: - Initialization

  /// Primary initializer with full DIP compliance
  public init(
    initialState: Feature.State,
    feature: Feature,
    taskManager: TaskManager = TaskManager()
  ) {
    self.feature = feature
    self._state = initialState
    self.taskManager = taskManager
    self.handler = feature.handle()

    let subsystem = Bundle.main.bundleIdentifier ?? "com.viewfeature.library"
    let featureName = String(describing: Feature.self)
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
  @discardableResult
  public func send(_ action: Feature.Action) -> Task<Void, Never> {
    Task { @MainActor in
      await self.processAction(action)
    }
  }

  // MARK: - Private Implementation

  private func processAction(_ action: Feature.Action) async {
    var mutableState = _state
    let actionTask = await handler.handle(action: action, state: &mutableState)
    _state = mutableState
    await executeTask(actionTask.storeTask)
  }

  private func executeTask(_ storeTask: StoreTask<Feature.Action, Feature.State>) async {
    switch storeTask {
    case .none:
      break

    case .run(let id, let operation, let onError):
      let errorHandler = createErrorHandler(from: onError)
      let backgroundTask = taskManager.executeTask(id: id, operation: operation, onError: errorHandler)
      await backgroundTask.value

    case .cancel(let id):
      taskManager.cancelTaskInternal(id: id)
    }
  }

  private func createErrorHandler(
    from onError: ((Error, inout Feature.State) -> Void)?
  ) -> ((Error) async -> Void)? {
    onError.map { handler -> ((Error) async -> Void) in
      { (error: Error) async in
        var currentState = self._state
        handler(error, &currentState)
        self._state = currentState
      }
    }
  }

  // MARK: - Task Management API

  /// Cancels a running task by its ID.
  ///
  /// This method provides direct task cancellation from the View layer.
  ///
  /// ## Recommended Approach: Action-Based Cancellation
  /// For better testability and state consistency, prefer using Actions:
  /// ```swift
  /// enum Action {
  ///   case startDownload
  ///   case cancelDownload
  /// }
  ///
  /// case .startDownload:
  ///   return .run(id: "download") { ... }
  ///
  /// case .cancelDownload:
  ///   return .cancel(id: "download")
  /// ```
  ///
  /// ## Direct Cancellation Use Cases
  /// Use this method for:
  /// - Emergency stops
  /// - User-initiated cancellations outside normal flow
  /// - Cleanup in View lifecycle (`.onDisappear`)
  ///
  /// ## Example
  /// ```swift
  /// Button("Cancel Download") {
  ///   store.cancelTask(id: "download")
  /// }
  /// ```
  ///
  /// - Parameter id: The task identifier (see ``TaskID`` for supported types)
  public func cancelTask<ID: TaskID>(id: ID) {
    taskManager.cancelTask(id: id)
  }

  public func cancelAllTasks() {
    taskManager.cancelAllTasks()
  }

  public var runningTaskCount: Int {
    taskManager.runningTaskCount
  }

  public func isTaskRunning<ID: TaskID>(id: ID) -> Bool {
    taskManager.isTaskRunning(id: id)
  }
}
