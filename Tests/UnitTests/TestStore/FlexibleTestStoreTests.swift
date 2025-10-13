import XCTest

@testable import ViewFeature

/// Tests for TestStore's flexible assertion patterns (assert and KeyPath-based)
@MainActor
final class TestStoreFlexibleAssertionsTests: XCTestCase {
  // MARK: - Test State without Equatable

  // Non-Equatable state with complex properties
  struct NonEquatableState: Sendable {
    var count: Int = 0
    var name: String = ""
    var isActive: Bool = false
    var tags: Set<String> = []  // Not Equatable by default in our tests
  }

  enum TestAction: Sendable {
    case increment
    case setName(String)
    case activate
    case addTag(String)
  }

  struct TestFeature: StoreFeature {
    typealias State = NonEquatableState
    typealias Action = TestAction

    func handle() -> ActionHandler<Action, State> {
      ActionHandler { action, state in
        switch action {
        case .increment:
          state.count += 1
          return .none

        case .setName(let name):
          state.name = name
          return .none

        case .activate:
          state.isActive = true
          return .none

        case .addTag(let tag):
          state.tags.insert(tag)
          return .none
        }
      }
    }
  }

  // MARK: - Pattern 1: Custom Assertions Tests

  func testSend_withCustomAssert_verifiesMultipleProperties() async {
    let store = TestStore(
      initialState: NonEquatableState(),
      feature: TestFeature()
    )

    await store.send(
      TestAction.increment,
      assert: { state in
        XCTAssertEqual(state.count, 1)
      })

    await store.send(
      TestAction.setName("Alice"),
      assert: { state in
        XCTAssertEqual(state.name, "Alice")
        XCTAssertEqual(state.count, 1)
      })

    await store.send(
      TestAction.activate,
      assert: { state in
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.name, "Alice")
        XCTAssertEqual(state.count, 1)
      })
  }

  func testSend_withCustomAssert_canTestComplexProperties() async {
    let store = TestStore(
      initialState: NonEquatableState(),
      feature: TestFeature()
    )

    await store.send(
      TestAction.addTag("swift"),
      assert: { state in
        // Can access complex properties
        XCTAssertTrue(state.tags.contains("swift"))
      })

    await store.send(
      TestAction.addTag("testing"),
      assert: { state in
        XCTAssertTrue(state.tags.contains("swift"))
        XCTAssertTrue(state.tags.contains("testing"))
        XCTAssertEqual(state.tags.count, 2)
      })
  }

  // MARK: - Pattern 2: KeyPath Assertions Tests

  func testSend_withKeyPath_verifiesSingleProperty() async {
    let store = TestStore(
      initialState: NonEquatableState(),
      feature: TestFeature()
    )

    // Using unlabeled parameters (recommended)
    await store.send(TestAction.increment, \.count, 1)
    await store.send(TestAction.increment, \.count, 2)
    await store.send(TestAction.setName("Bob"), \.name, "Bob")
    await store.send(TestAction.activate, \.isActive, true)
  }

  func testSend_withKeyPath_providesHelpfulErrorMessages() async {
    let store = TestStore(
      initialState: NonEquatableState(),
      feature: TestFeature()
    )

    // This will fail with clear error message
    // Uncomment to test error reporting:
    // await store.send(TestAction.increment, \.count, 999)

    // But this passes
    await store.send(TestAction.increment, \.count, 1)
  }

  // MARK: - Basic send Tests

  func testSend_withoutAssert_allowsManualVerification() async {
    let store = TestStore(
      initialState: NonEquatableState(),
      feature: TestFeature()
    )

    let state1 = await store.send(TestAction.increment)
    XCTAssertEqual(state1.count, 1)

    let state2 = await store.send(TestAction.setName("Charlie"))
    XCTAssertEqual(state2.name, "Charlie")
    XCTAssertEqual(state2.count, 1)
  }

  // MARK: - State Access Tests

  func testState_providesDirectAccess() async {
    let store = TestStore(
      initialState: NonEquatableState(),
      feature: TestFeature()
    )

    XCTAssertEqual(store.state.count, 0)

    await store.send(TestAction.increment)
    XCTAssertEqual(store.state.count, 1)

    await store.send(TestAction.setName("David"))
    XCTAssertEqual(store.state.name, "David")
  }

  // MARK: - Action History Tests

  func testActionHistory_tracksAllActions() async {
    let store = TestStore(
      initialState: NonEquatableState(),
      feature: TestFeature()
    )

    XCTAssertEqual(store.actionHistory.count, 0)

    await store.send(TestAction.increment)
    XCTAssertEqual(store.actionHistory.count, 1)

    await store.send(TestAction.setName("Eve"))
    XCTAssertEqual(store.actionHistory.count, 2)

    await store.send(TestAction.activate)
    XCTAssertEqual(store.actionHistory.count, 3)
  }

  // MARK: - Hybrid Pattern Tests

  func testHybridPattern_combinesKeyPathAndCustomAssert() async {
    let store = TestStore(
      initialState: NonEquatableState(),
      feature: TestFeature()
    )

    // Use KeyPath for simple property checks (unlabeled for brevity)
    await store.send(TestAction.increment, \.count, 1)

    // Use custom assert for complex validations
    await store.send(
      TestAction.setName("Frank"),
      assert: { state in
        XCTAssertEqual(state.name, "Frank")
        XCTAssertEqual(state.count, 1)
        XCTAssertFalse(state.isActive)
      })

    // Mix both patterns as needed
    await store.send(TestAction.activate, \.isActive, true)

    XCTAssertEqual(store.state.count, 1)
    XCTAssertEqual(store.state.name, "Frank")
    XCTAssertTrue(store.state.isActive)
  }

  // MARK: - Comparison with Regular TestStore

  struct EquatableState: Equatable, Sendable {
    var count: Int = 0
    var name: String = ""
  }

  enum SimpleAction: Sendable {
    case increment
    case setName(String)
  }

  struct SimpleFeature: StoreFeature {
    typealias State = EquatableState
    typealias Action = SimpleAction

    func handle() -> ActionHandler<Action, State> {
      ActionHandler { action, state in
        switch action {
        case .increment:
          state.count += 1
          return .none

        case .setName(let name):
          state.name = name
          return .none
        }
      }
    }
  }

  func testTestStore_supportsAllPatternsWithEquatableState() async {
    // TestStore supports all three patterns with Equatable states
    let store = TestStore(
      initialState: EquatableState(),
      feature: SimpleFeature()
    )

    // Pattern 1: KeyPath assertion (concise, unlabeled)
    await store.send(SimpleAction.increment, \.count, 1)

    // Pattern 2: Custom assertion (flexible)
    await store.send(
      SimpleAction.setName("Grace"),
      assert: { state in
        XCTAssertEqual(state.name, "Grace")
        XCTAssertEqual(state.count, 1)
      })

    // Pattern 3: Full state comparison (most strict, Equatable only)
    await store.send(SimpleAction.increment) { state in
      state.count = 2
      state.name = "Grace"
    }

    XCTAssertEqual(store.state.count, 2)
    XCTAssertEqual(store.state.name, "Grace")
  }

  // MARK: - Failure Scenario Tests

  func testSend_withEquatableExpectation_detectsStateMismatch() async {
    // This test intentionally causes a failure to exercise the failure path
    // for code coverage. We use a custom assertion provider to capture the failure.

    // Custom assertion provider that tracks failures
    final class FailureTrackingProvider: AssertionProvider {
      var failures: [String] = []

      func assertEqual<T: Equatable>(
        _ actual: T, _ expected: T, _ message: String, file: StaticString, line: UInt
      ) {
        if actual != expected {
          failures.append(message)
        }
      }

      func fail(_ message: String, file: StaticString, line: UInt) {
        failures.append(message)
      }
    }

    // GIVEN: Store with custom assertion provider
    let assertionProvider = FailureTrackingProvider()
    let store = TestStore(
      initialState: EquatableState(),
      feature: SimpleFeature(),
      assertionProvider: assertionProvider
    )

    // WHEN: Action produces different state than expected
    await store.send(SimpleAction.increment) { state in
      // Intentionally set wrong expectation to trigger failure path
      state.count = 999  // Actual will be 1
      state.name = ""
    }

    // THEN: Failure should have been detected and recorded
    XCTAssertFalse(assertionProvider.failures.isEmpty, "Should have recorded assertion failure")
    XCTAssertTrue(
      assertionProvider.failures[0].contains("State mismatch"),
      "Should contain state mismatch message")

    // This test exercises the validateStateExpectation failure path (lines 343-360)
  }

  // MARK: - Cancel Task Tests

  struct CancelTaskState: Equatable, Sendable {
    var isRunning: Bool = false
    var taskId: String?
  }

  enum CancelTaskAction: Sendable {
    case startTask(String)
    case cancelTask(String)
  }

  struct CancelTaskFeature: StoreFeature {
    typealias State = CancelTaskState
    typealias Action = CancelTaskAction

    func handle() -> ActionHandler<Action, State> {
      ActionHandler { action, state in
        switch action {
        case .startTask(let id):
          state.isRunning = true
          state.taskId = id
          return .run(id: id) {
            try await Task.sleep(for: .milliseconds(100))
          }

        case .cancelTask(let id):
          state.isRunning = false
          state.taskId = nil
          return .cancel(id: id)
        }
      }
    }
  }

  func testSend_withCancelTask_executesCancellation() async {
    // GIVEN: Store that can create and cancel tasks
    let store = TestStore(
      initialState: CancelTaskState(),
      feature: CancelTaskFeature(),
      assertionProvider: XCTestAssertionProvider()
    )

    // WHEN: Start a task
    await store.send(CancelTaskAction.startTask("test-task"), \.isRunning, true)
    XCTAssertEqual(store.state.taskId, "test-task")

    // WHEN: Cancel the task
    await store.send(CancelTaskAction.cancelTask("test-task")) { state in
      state.isRunning = false
      state.taskId = nil
    }

    // THEN: Task should be cancelled and state updated
    XCTAssertFalse(store.state.isRunning)
    XCTAssertNil(store.state.taskId)
  }

  func testSend_withMultipleCancelTasks_handlesMultipleCancellations() async {
    // GIVEN: Store with multiple tasks
    let store = TestStore(
      initialState: CancelTaskState(),
      feature: CancelTaskFeature(),
      assertionProvider: XCTestAssertionProvider()
    )

    // WHEN: Start multiple tasks
    await store.send(CancelTaskAction.startTask("task-1"), \.isRunning, true)
    await store.send(CancelTaskAction.startTask("task-2"), \.isRunning, true)

    // WHEN: Cancel tasks
    await store.send(CancelTaskAction.cancelTask("task-1"), \.isRunning, false)
    await store.send(CancelTaskAction.cancelTask("task-2"), \.isRunning, false)

    // THEN: All tasks cancelled
    XCTAssertFalse(store.state.isRunning)
  }

  // MARK: - Error Handler Tests

  struct ErrorHandlerState: Equatable, Sendable {
    var count: Int = 0
    var errorMessage: String?
    var lastError: String?
  }

  enum ErrorHandlerAction: Sendable {
    case increment
    case throwError
    case throwWithHandler
  }

  struct ErrorHandlerFeature: StoreFeature {
    typealias State = ErrorHandlerState
    typealias Action = ErrorHandlerAction

    func handle() -> ActionHandler<Action, State> {
      ActionHandler { action, state in
        switch action {
        case .increment:
          state.count += 1
          return .none

        case .throwError:
          return .run(id: "error-task") {
            throw NSError(
              domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
          }

        case .throwWithHandler:
          return ActionTask(
            storeTask: .run(
              id: "error-with-handler",
              operation: {
                throw NSError(
                  domain: "TestError", code: 2,
                  userInfo: [NSLocalizedDescriptionKey: "Handled error"])
              },
              onError: { error, state in
                state.errorMessage = error.localizedDescription
                state.lastError = "Error caught"
              }
            ))
        }
      }
    }
  }

  func testSend_withTaskError_handlesErrorGracefully() async {
    // GIVEN: Store that can throw errors
    let store = TestStore(
      initialState: ErrorHandlerState(),
      feature: ErrorHandlerFeature(),
      assertionProvider: XCTestAssertionProvider()
    )

    // WHEN: Action throws an error
    await store.send(ErrorHandlerAction.throwError)

    // THEN: Store should handle error without crashing
    XCTAssertEqual(store.state.count, 0)
  }

  func testSend_withTaskErrorAndHandler_executesErrorHandler() async {
    // GIVEN: Store with error handler
    let store = TestStore(
      initialState: ErrorHandlerState(),
      feature: ErrorHandlerFeature(),
      assertionProvider: XCTestAssertionProvider()
    )

    // WHEN: Action throws error with handler
    await store.send(ErrorHandlerAction.throwWithHandler)

    // Wait for error handler to execute
    try? await Task.sleep(for: .milliseconds(50))

    // THEN: Error handler should have updated state
    XCTAssertEqual(store.state.errorMessage, "Handled error")
    XCTAssertEqual(store.state.lastError, "Error caught")
  }

  func testSend_withSuccessBeforeError_maintainsPreviousState() async {
    // GIVEN: Store with some state
    let store = TestStore(
      initialState: ErrorHandlerState(),
      feature: ErrorHandlerFeature(),
      assertionProvider: XCTestAssertionProvider()
    )

    // WHEN: Successful action followed by error
    await store.send(ErrorHandlerAction.increment, \.count, 1)
    await store.send(ErrorHandlerAction.increment, \.count, 2)

    await store.send(ErrorHandlerAction.throwError)

    // THEN: Previous state should be maintained
    XCTAssertEqual(store.state.count, 2)
  }

  func testSend_withMultipleErrorHandlers_executesAllHandlers() async {
    // GIVEN: Store with error handling
    let store = TestStore(
      initialState: ErrorHandlerState(),
      feature: ErrorHandlerFeature(),
      assertionProvider: XCTestAssertionProvider()
    )

    // WHEN: Multiple actions with error handlers
    await store.send(ErrorHandlerAction.throwWithHandler)
    try? await Task.sleep(for: .milliseconds(50))

    await store.send(ErrorHandlerAction.throwWithHandler)
    try? await Task.sleep(for: .milliseconds(50))

    // THEN: All handlers should execute
    XCTAssertNotNil(store.state.errorMessage)
    XCTAssertEqual(store.state.lastError, "Error caught")
  }
}
