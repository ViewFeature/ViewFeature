import Foundation

/// A protocol that defines the core behavior of a feature in the ViewFeature architecture.
///
/// `StoreFeature` is the fundamental building block for creating modular, testable features.
/// Each feature encapsulates its own state, actions, and business logic, following the
/// single responsibility principle.
///
/// ## Overview
/// Features provide a clean separation of concerns by:
/// - Defining their own state and action types
/// - Implementing domain-specific logic in a testable manner
/// - Supporting asynchronous operations through task management
/// - Enabling composition with middleware and error handling
///
/// ## Implementation Pattern
/// ```swift
/// struct UserFeature: StoreFeature {
///   // 1. Define your state (nested)
///   @Observable
///   final class State {
///     var user: User?
///     var isLoading = false
///     var isAuthenticated = false
///
///     init(user: User? = nil, isLoading: Bool = false, isAuthenticated: Bool = false) {
///       self.user = user
///       self.isLoading = isLoading
///       self.isAuthenticated = isAuthenticated
///     }
///   }
///
///   // 2. Define your actions (nested)
///   enum Action: Sendable {
///     case login(credentials: Credentials)
///     case loginSuccess(User)
///     case logout
///     case setLoading(Bool)
///   }
///
///   // 3. Create your action handler
///   func handle() -> ActionHandler<Action, State> {
///     ActionHandler { action, state in
///       switch action {
///       case .login(let credentials):
///         state.isLoading = true          // ← Direct state mutation
///         return .run(id: "login") {      // ← Async task
///           let user = try await authService.login(credentials)
///           await store.send(.loginSuccess(user))
///         }
///
///       case .loginSuccess(let user):
///         state.user = user
///         state.isAuthenticated = true
///         state.isLoading = false
///         return .none
///
///       case .logout:
///         state.user = nil                // ← Multiple mutations
///         state.isAuthenticated = false   // ← in single action
///         return .none                  // ← No side effects
///
///       case .setLoading(let loading):
///         state.isLoading = loading
///         return .none
///       }
///     }
///   }
/// }
/// ```
///
/// ## Task Management
/// Your action handlers can return different task types:
///
/// - **`ActionTask.none`**: For synchronous state-only changes
/// - **`ActionTask.run(id:operation:)`**: For asynchronous operations (network, database, etc.)
/// - **`ActionTask.cancel(id:)`**: For cancelling running tasks by ID
///
/// ## Best Practices
/// - Keep features focused on a single domain (user management, settings, etc.)
/// - Use @Observable class for state to enable SwiftUI observation
/// - Define State and Action as nested types within the feature
/// - Make actions descriptive and domain-specific
/// - Handle errors gracefully using `.run` with error handling
///
/// ## Topics
/// ### Associated Types
/// - ``Action``
/// - ``State``
///
/// ### Creating Handlers
/// - ``handle()``
///
/// ### Related Documentation
/// - ``Store``
/// - ``ActionHandler``
/// - ``ActionTask``
public protocol StoreFeature: Sendable {
  /// The type representing actions that can be sent to this feature.
  ///
  /// Actions describe events or user intentions that trigger state changes.
  /// They must conform to `Sendable` for safe concurrency.
  /// Define as a nested enum within your feature for better namespacing.
  ///
  /// ## Example
  /// ```swift
  /// struct CounterFeature: StoreFeature {
  ///   enum Action: Sendable {
  ///     case increment
  ///     case decrement
  ///     case reset
  ///   }
  /// }
  /// ```
  associatedtype Action: Sendable

  /// The type representing the state managed by this feature.
  ///
  /// State should be an @Observable class for SwiftUI integration.
  /// Equatable conformance is optional but enables TestStore's full state comparison.
  /// Define as a nested class within your feature for better namespacing.
  ///
  /// ## Example
  /// ```swift
  /// struct CounterFeature: StoreFeature {
  ///   @Observable
  ///   final class State {
  ///     var count = 0
  ///     var lastUpdated: Date?
  ///
  ///     init(count: Int = 0, lastUpdated: Date? = nil) {
  ///       self.count = count
  ///       self.lastUpdated = lastUpdated
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// - Note: @Observable requires class types for SwiftUI observation
  associatedtype State

  /// Creates an ActionHandler that processes actions for this feature.
  ///
  /// The handler receives actions and an `inout` state parameter, allowing direct
  /// mutation for optimal performance. It returns an ``ActionTask`` to handle
  /// any asynchronous side effects.
  ///
  /// ## Example
  /// ```swift
  /// func handle() -> ActionHandler<Action, State> {
  ///   ActionHandler { action, state in
  ///     switch action {
  ///     case .increment:
  ///       state.count += 1
  ///       return .none
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// - Returns: An ActionHandler configured for this feature's action handling
  func handle() -> ActionHandler<Action, State>
}

