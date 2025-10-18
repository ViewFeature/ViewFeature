import Foundation
import Logging
import Observation

/// The main store for managing application state and dispatching actions.
///
/// `Store` provides a Redux-like unidirectional data flow architecture for SwiftUI apps
/// with fire-and-forget action dispatching and MainActor-isolated state management.
///
/// ## Key Characteristics
/// - **MainActor Isolation**: All state mutations occur on the MainActor for thread-safe UI updates
/// - **Fire-and-Forget API**: Actions can be dispatched without awaiting, or awaited when needed
/// - **Sequential Processing**: Actions are processed sequentially to ensure state consistency
///
/// The Store coordinates between state management, action processing, and task execution while
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

    /// Dispatches an action and processes it through the handler using a fire-and-forget pattern.
    ///
    /// This method provides flexible action dispatching:
    /// - **Fire-and-forget**: Call without awaiting for non-blocking UI operations
    /// - **Await completion**: Use `await store.send(...).value` when you need to wait
    ///
    /// All action processing occurs on the **MainActor**, ensuring thread-safe state mutations
    /// and seamless integration with SwiftUI.
    ///
    /// - Parameter action: The action to dispatch
    /// - Returns: A Task that completes when the action processing finishes.
    ///   You can await this task if you need to ensure the action is fully processed.
    ///
    /// ## Fire-and-Forget Pattern
    /// ```swift
    /// // Fire-and-forget: Non-blocking, perfect for UI interactions
    /// Button("Increment") {
    ///   store.send(.increment)  // Returns immediately
    /// }
    ///
    /// // Wait for completion: Useful for testing or ensuring side effects complete
    /// await store.send(.loadData).value  // Waits until data is loaded
    /// ```
    ///
    /// ## MainActor Execution
    /// All actions and state mutations execute on the **MainActor**:
    /// ```swift
    /// // This action handler runs on MainActor
    /// ActionHandler { action, state in
    ///   switch action {
    ///   case .increment:
    ///     state.count += 1  // ✅ Safe MainActor mutation
    ///     return .none
    ///   }
    /// }
    /// ```
    ///
    /// ## Sequential Processing
    /// Actions are processed **sequentially** on the MainActor. If an action returns
    /// a `.run` task, the Store will await its completion before processing the next action.
    ///
    /// ```swift
    /// store.send(.longRunningTask)  // Takes 5 seconds
    /// store.send(.quickTask)        // Waits until longRunningTask completes
    /// ```
    ///
    /// **Why sequential?**
    /// - Ensures state consistency (no concurrent mutations)
    /// - Simplifies reasoning about action order
    /// - Prevents race conditions
    ///
    /// If you need truly concurrent background work, dispatch it inside the `.run` block:
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

    // ========================================
    // Sequential Action Processing
    // ========================================
    // Actions are processed sequentially to ensure state consistency and prevent race conditions.
    // This method awaits both the handler execution AND the task execution, ensuring the next
    // action cannot start until the current one (including its async task) completes.
    //
    // Why sequential?
    // - State mutations are predictable and ordered
    // - No concurrent access to mutable state
    // - Simpler mental model for developers
    //
    // See Store.send() DocC for full sequential execution rationale.
    private func processAction(_ action: F.Action) async {
        let actionTask = await handler.handle(action: action, state: _state)
        await executeTask(actionTask.storeTask)
    }

    private func executeTask(_ storeTask: StoreTask<F.Action, F.State>) async {
        switch storeTask {
        case .none:
            break

        case .run(let id, let operation, let onError, let cancelInFlight, let priority):
            // Cancel existing task with same ID if cancelInFlight is true
            if cancelInFlight {
                taskManager.cancelTasksInternal(ids: [id])
            }

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
                },
                priority: priority
            )

            // ========================================
            // Why await task.value?
            // ========================================
            // This await is CRITICAL for sequential action processing. Without it, the next action
            // would start immediately while this task is still running, breaking our sequential
            // execution guarantee.
            //
            // Example without await:
            //   send(.longTask)   // Starts 5-second task, returns immediately
            //   send(.quickTask)  // Starts while longTask is still running ❌
            //
            // Example with await:
            //   send(.longTask)   // Starts 5-second task, waits for completion
            //   send(.quickTask)  // Starts only after longTask completes ✅
            //
            // This ensures:
            // - Actions complete in the order they were sent
            // - State mutations are serialized (no race conditions)
            // - Predictable execution flow for developers
            //
            // TaskManager tracks the task for cancellation, but doesn't enforce sequential execution.
            // That's the Store's responsibility, implemented here via await.
            //
            // See Store.send() DocC (lines 128-156) for full sequential execution rationale.
            await task.value

        case .cancels(let ids):
            taskManager.cancelTasksInternal(ids: ids)
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
