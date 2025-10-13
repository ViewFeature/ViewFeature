import Foundation

/// A testing-oriented store for validating feature behavior.
///
/// `TestStore` provides a deterministic environment for testing your features.
/// It executes actions synchronously (awaiting tasks) and provides multiple assertion
/// patterns to verify that actions produce expected state changes.
///
/// ## Key Features
/// - Synchronous action execution for predictable tests
/// - Multiple assertion patterns (full state, custom, KeyPath-based)
/// - Works with both Equatable and non-Equatable states
/// - Action history tracking for behavior verification
/// - Support for async tasks (executed immediately)
///
/// ## Testing Patterns
///
/// ### Pattern 1: Full State Comparison (Equatable required)
/// ```swift
/// struct CounterFeature: StoreFeature {
///   @Observable
///   final class State: Equatable {
///     var count = 0
///
///     init(count: Int = 0) {
///       self.count = count
///     }
///
///     static func == (lhs: State, rhs: State) -> Bool {
///       lhs.count == rhs.count
///     }
///   }
///
///   enum Action: Sendable {
///     case increment
///   }
///
///   func handle() -> ActionHandler<Action, State> {
///     ActionHandler { action, state in
///       switch action {
///       case .increment:
///         state.count += 1
///         return .none
///       }
///     }
///   }
/// }
///
/// func testIncrement() async {
///   let store = TestStore(
///     initialState: CounterFeature.State(count: 0),
///     feature: CounterFeature()
///   )
///
///   await store.send(.increment) { state in
///     state.count = 1  // TestStore validates entire state equality
///   }
/// }
/// ```
///
/// ### Pattern 2: Custom Assertions (No Equatable required)
/// ```swift
/// struct AppFeature: StoreFeature {
///   @Observable
///   final class State {
///     var user: User?
///     var isLoading = false
///   }
///
///   enum Action: Sendable {
///     case loadUser
///   }
///
///   func handle() -> ActionHandler<Action, State> {
///     ActionHandler { action, state in
///       switch action {
///       case .loadUser:
///         state.isLoading = true
///         state.user = User(name: "Alice")
///         return .none
///       }
///     }
///   }
/// }
///
/// func testLoadUser() async {
///   let store = TestStore(
///     initialState: AppFeature.State(),
///     feature: AppFeature()
///   )
///
///   await store.send(.loadUser, assert: { state in
///     XCTAssertEqual(state.user?.name, "Alice")
///     XCTAssertTrue(state.isLoading)
///   })
/// }
/// ```
///
/// ### Pattern 3: KeyPath Assertions (Concise, no Equatable required)
/// ```swift
/// func testCounter() async {
///   let store = TestStore(
///     initialState: CounterFeature.State(),
///     feature: CounterFeature()
///   )
///
///   // Recommended: Unlabeled parameters for brevity
///   await store.send(.increment, \.count, 1)
///   await store.send(.increment, \.count, 2)
///
///   // Alternative: Labeled parameters for clarity
///   await store.send(.increment, expecting: \.count, toBe: 1)
/// }
/// ```
///
/// ## Topics
/// ### Creating Test Stores
/// - ``init(initialState:feature:assertionProvider:)``
///
/// ### Sending Actions
/// - ``send(_:file:line:)``
/// - ``send(_:expecting:file:line:)`` (Equatable State)
/// - ``send(_:assert:file:line:)`` (Any State)
/// - ``send(_:_:_:file:line:)`` (KeyPath assertion, unlabeled - recommended)
/// - ``send(_:expecting:toBe:file:line:)`` (KeyPath assertion, labeled)
///
/// ### Inspecting State
/// - ``state``
/// - ``actionHistory``
public final class TestStore<Feature: StoreFeature> {
    private var _state: Feature.State
    private let feature: Feature
    private let handler: ActionHandler<Feature.Action, Feature.State>
    private var _actionHistory: [Feature.Action] = []
    private let assertionProvider: AssertionProvider

    /// The current state of the store.
    ///
    /// Access this property to inspect the current state after sending actions.
    ///
    /// ## Example
    /// ```swift
    /// await store.send(.increment)
    /// XCTAssertEqual(store.state.count, 1)
    /// ```
    public var state: Feature.State {
        _state
    }

    /// The history of all actions sent to this store.
    ///
    /// Useful for verifying that the correct sequence of actions was dispatched,
    /// especially when testing complex workflows or side effects.
    ///
    /// ## Example
    /// ```swift
    /// await store.send(.login)
    /// await store.send(.fetchProfile)
    /// XCTAssertEqual(store.actionHistory.count, 2)
    /// ```
    public var actionHistory: [Feature.Action] {
        _actionHistory
    }

    /// Creates a new TestStore with the given initial state and feature.
    ///
    /// - Parameters:
    ///   - initialState: The starting state for the store
    ///   - feature: The feature implementation to test
    ///   - assertionProvider: The assertion provider to use (defaults to PrintAssertionProvider)
    ///
    /// ## Example
    /// ```swift
    /// // In test targets (explicitly use XCTest assertions)
    /// let store = TestStore(
    ///   initialState: CounterFeature.State(count: 0),
    ///   feature: CounterFeature(),
    ///   assertionProvider: XCTestAssertionProvider()
    /// )
    ///
    /// // In app targets (uses print-based assertions by default)
    /// let store = TestStore(
    ///   initialState: CounterFeature.State(count: 0),
    ///   feature: CounterFeature()
    /// )
    /// ```
    public init(
        initialState: Feature.State,
        feature: Feature,
        assertionProvider: AssertionProvider = PrintAssertionProvider()
    ) {
        self._state = initialState
        self.feature = feature
        self.handler = feature.handle()
        self.assertionProvider = assertionProvider
    }

    /// Sends an action to the store and returns the resulting state.
    ///
    /// The action is processed synchronously, including any async tasks it triggers.
    /// This allows for predictable testing of action sequences.
    ///
    /// - Parameters:
    ///   - action: The action to send
    ///   - file: The file where this method is called (for error reporting)
    ///   - line: The line where this method is called (for error reporting)
    /// - Returns: The new state after processing the action
    ///
    /// ## Example
    /// ```swift
    /// let newState = await store.send(.increment)
    /// XCTAssertEqual(newState.count, 1)
    /// ```
    @discardableResult
    public func send(
        _ action: Feature.Action,
        file: StaticString = #file,
        line: UInt = #line
    ) async -> Feature.State {
        _actionHistory.append(action)

        var localState = _state
        let actionTask = await handler.handle(action: action, state: &localState)
        _state = localState
        await executeStoreTask(actionTask.storeTask)

        return _state
    }

    /// Sends an action and validates that the state changes as expected.
    ///
    /// This method is the preferred way to test actions when State is Equatable,
    /// as it provides clear error messages when the actual state doesn't match expectations.
    ///
    /// - Parameters:
    ///   - action: The action to send
    ///   - expecting: A closure that mutates a copy of the previous state to express expectations
    ///   - file: The file where this method is called (for error reporting)
    ///   - line: The line where this method is called (for error reporting)
    /// - Returns: The new state after processing the action
    ///
    /// ## Example
    /// ```swift
    /// await store.send(.increment) { state in
    ///   state.count = 1  // Express expected change
    /// }
    /// ```
    ///
    /// - Note: Requires State to conform to Equatable. Use `send(_:assert:)` for non-Equatable states.
    @discardableResult
    public func send(
        _ action: Feature.Action,
        expecting: (inout Feature.State) -> Void,
        file: StaticString = #file,
        line: UInt = #line
    ) async -> Feature.State where Feature.State: Equatable {
        let previousState = _state
        let newState = await send(action, file: file, line: line)

        validateStateExpectation(
            previousState: previousState,
            actualState: newState,
            expecting: expecting,
            file: file,
            line: line
        )

        return newState
    }

    /// Sends an action with custom assertion logic.
    ///
    /// Use this method when your State is not Equatable or when you need custom
    /// assertions beyond simple equality checking.
    ///
    /// - Parameters:
    ///   - action: The action to send
    ///   - assert: A closure that performs custom assertions on the resulting state
    ///   - file: The file where this method is called (for error reporting)
    ///   - line: The line where this method is called (for error reporting)
    /// - Returns: The new state after processing the action
    ///
    /// ## Example
    /// ```swift
    /// await store.send(.loadUser, assert: { state in
    ///     XCTAssertEqual(state.user.name, "Alice")
    ///     XCTAssertTrue(state.user.isActive)
    /// })
    /// ```
    @discardableResult
    public func send(
        _ action: Feature.Action,
        assert: (Feature.State) -> Void,
        file: StaticString = #file,
        line: UInt = #line
    ) async -> Feature.State {
        let newState = await send(action, file: file, line: line)
        assert(newState)
        return newState
    }

    /// Sends an action and asserts a specific property value using a KeyPath.
    ///
    /// This is the most concise testing method. Use it when you want to verify
    /// a single property change without writing full assertion closures.
    ///
    /// - Parameters:
    ///   - action: The action to send
    ///   - keyPath: A KeyPath to the property to assert
    ///   - expectedValue: The expected value of the property
    ///   - file: The file where this method is called (for error reporting)
    ///   - line: The line where this method is called (for error reporting)
    /// - Returns: The new state after processing the action
    ///
    /// ## Example
    /// ```swift
    /// // Unlabeled parameters (recommended for brevity)
    /// await store.send(.increment, \.count, 1)
    /// await store.send(.setName("Alice"), \.name, "Alice")
    ///
    /// // Labeled parameters (more explicit)
    /// await store.send(.increment, expecting: \.count, toBe: 1)
    /// await store.send(.setName("Alice"), expecting: \.name, toBe: "Alice")
    /// ```
    @discardableResult
    public func send<Value: Equatable>(
        _ action: Feature.Action,
        _ keyPath: KeyPath<Feature.State, Value>,
        _ expectedValue: Value,
        file: StaticString = #file,
        line: UInt = #line
    ) async -> Feature.State {
        let newState = await send(action, file: file, line: line)
        let actualValue = newState[keyPath: keyPath]

        assertionProvider.assertEqual(
            actualValue,
            expectedValue,
            "Property mismatch at keyPath \(keyPath)",
            file: file,
            line: line
        )

        return newState
    }

    /// Sends an action and asserts a specific property value using a KeyPath (labeled variant).
    ///
    /// This is an alternative form with explicit parameter labels for clarity.
    /// Most users prefer the unlabeled variant for brevity.
    ///
    /// - Parameters:
    ///   - action: The action to send
    ///   - keyPath: A KeyPath to the property to assert
    ///   - expectedValue: The expected value of the property
    ///   - file: The file where this method is called (for error reporting)
    ///   - line: The line where this method is called (for error reporting)
    /// - Returns: The new state after processing the action
    ///
    /// ## Example
    /// ```swift
    /// await store.send(.increment, expecting: \.count, toBe: 1)
    /// await store.send(.setName("Alice"), expecting: \.user.name, toBe: "Alice")
    /// ```
    @discardableResult
    public func send<Value: Equatable>(
        _ action: Feature.Action,
        expecting keyPath: KeyPath<Feature.State, Value>,
        toBe expectedValue: Value,
        file: StaticString = #file,
        line: UInt = #line
    ) async -> Feature.State {
        // Delegate to the unlabeled variant
        await send(action, keyPath, expectedValue, file: file, line: line)
    }

    private func validateStateExpectation(
        previousState: Feature.State,
        actualState: Feature.State,
        expecting: (inout Feature.State) -> Void,
        file: StaticString,
        line: UInt
    ) where Feature.State: Equatable {
        var expectedState = previousState
        expecting(&expectedState)

        if actualState != expectedState {
            assertionProvider.fail(
                """
        State mismatch

        Expected:
        \(String(describing: expectedState))

        Actual:
        \(String(describing: actualState))
        """,
                file: file,
                line: line
            )
        }
    }

    private func executeStoreTask(_ storeTask: StoreTask<Feature.Action, Feature.State>) async {
        switch storeTask {
        case .none:
            return
        case .run(_, let operation, let onError):
            do {
                try await operation()
            } catch {
                if let errorHandler = onError {
                    errorHandler(error, &_state)
                }
            }
        case .cancel:
            return
        }
    }
}
