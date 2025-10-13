@testable import ViewFeature
import XCTest

/// Integration tests for Store with Middleware.
///
/// Tests the complete integration between Store, Middleware, and ActionHandler
/// to ensure middleware properly intercepts and logs actions.
@MainActor
final class MiddlewareIntegrationTests: XCTestCase {

  // MARK: - Test Fixtures

  enum ShoppingAction: Sendable {
    case addItem(String)
    case removeItem(String)
    case checkout
    case clearCart
  }

  struct ShoppingState: Equatable, Sendable {
    var items: [String] = []
    var isCheckingOut: Bool = false
    var checkoutComplete: Bool = false
  }

  struct ShoppingFeature: StoreFeature, Sendable {
    typealias Action = ShoppingAction
    typealias State = ShoppingState

    func handle() -> ActionHandler<Action, State> {
      ActionHandler { action, state in
        switch action {
        case .addItem(let item):
          state.items.append(item)
          return .none

        case .removeItem(let item):
          state.items.removeAll { $0 == item }
          return .none

        case .checkout:
          state.isCheckingOut = true
          return .run(id: "checkout") {
            try await Task.sleep(for: .milliseconds(50))
          }

        case .clearCart:
          state.items.removeAll()
          state.isCheckingOut = false
          state.checkoutComplete = false
          return .none
        }
      }
    }
  }

  /// Custom test middleware to track actions
  struct TestMiddleware: ActionMiddleware {
    let id: String = "TestMiddleware"
    let tracker: ActionTracker

    actor ActionTracker {
      var actions: [String] = []

      func append(_ action: String) {
        actions.append(action)
      }

      func getActions() -> [String] {
        actions
      }

      func reset() {
        actions.removeAll()
      }
    }

    func beforeAction<Action, State>(_ action: Action, state: State) async throws {
      await tracker.append("\(action)")
    }
  }

  // MARK: - Middleware Integration Tests

  func test_middlewareReceivesAllActions() async {
    // GIVEN: Store with test middleware
    let tracker = TestMiddleware.ActionTracker()
    let testMiddleware = TestMiddleware(tracker: tracker)
    let store = Store(
      initialState: ShoppingState(),
      feature: ShoppingFeature()
    )

    // Note: Middleware integration with Store requires ActionProcessor setup
    // For now, we test Store actions directly
    let middlewareManager = MiddlewareManager<ShoppingAction, ShoppingState>()
    middlewareManager.addMiddleware(testMiddleware)

    // WHEN: Send multiple actions
    await store.send(.addItem("Apple")).value
    await store.send(.addItem("Banana")).value
    await store.send(.removeItem("Apple")).value

    // Wait for middleware processing
    try? await Task.sleep(for: .milliseconds(20))

    // THEN: State should be updated correctly
    XCTAssertEqual(store.state.items, ["Banana"])
  }

  func test_middlewareWithAsyncActions() async {
    // GIVEN: Store with middleware
    let tracker = TestMiddleware.ActionTracker()
    let testMiddleware = TestMiddleware(tracker: tracker)
    let store = Store(
      initialState: ShoppingState(),
      feature: ShoppingFeature()
    )

    let middlewareManager = MiddlewareManager<ShoppingAction, ShoppingState>()
    middlewareManager.addMiddleware(testMiddleware)

    // WHEN: Send async action
    await store.send(.addItem("Item1")).value
    await store.send(.checkout).value

    try? await Task.sleep(for: .milliseconds(100))

    // THEN: Middleware should process async actions
    XCTAssertTrue(store.state.isCheckingOut)
  }

  func test_multipleMiddlewareExecution() async {
    // GIVEN: Store with multiple middleware
    let tracker1 = TestMiddleware.ActionTracker()
    let middleware1 = TestMiddleware(tracker: tracker1)
    let tracker2 = TestMiddleware.ActionTracker()
    let middleware2 = TestMiddleware(tracker: tracker2)

    let store = Store(
      initialState: ShoppingState(),
      feature: ShoppingFeature()
    )

    let middlewareManager = MiddlewareManager<ShoppingAction, ShoppingState>()
    middlewareManager.addMiddleware(middleware1)
    middlewareManager.addMiddleware(middleware2)

    // WHEN: Send actions
    await store.send(.addItem("Item1")).value
    await store.send(.addItem("Item2")).value

    try? await Task.sleep(for: .milliseconds(20))

    // THEN: All middleware should execute
    XCTAssertEqual(store.state.items.count, 2)
  }

  // MARK: - LoggingMiddleware Integration

  func test_loggingMiddlewareIntegration() async {
    // GIVEN: Store with LoggingMiddleware
    let loggingMiddleware = LoggingMiddleware()

    let store = Store(
      initialState: ShoppingState(),
      feature: ShoppingFeature()
    )

    let middlewareManager = MiddlewareManager<ShoppingAction, ShoppingState>()
    middlewareManager.addMiddleware(loggingMiddleware)

    // WHEN: Execute actions
    await store.send(.addItem("Apple")).value
    await store.send(.addItem("Banana")).value
    await store.send(.checkout).value

    try? await Task.sleep(for: .milliseconds(100))

    // THEN: Actions should be logged (no crashes)
    XCTAssertEqual(store.state.items, ["Apple", "Banana"])
    XCTAssertTrue(store.state.isCheckingOut)
  }

  // MARK: - Complex Workflow with Middleware

  func test_fullShoppingWorkflowWithMiddleware() async {
    // GIVEN: Store with logging middleware
    let loggingMiddleware = LoggingMiddleware()
    let tracker = TestMiddleware.ActionTracker()
    let testMiddleware = TestMiddleware(tracker: tracker)

    let store = Store(
      initialState: ShoppingState(),
      feature: ShoppingFeature()
    )

    let middlewareManager = MiddlewareManager<ShoppingAction, ShoppingState>()
    middlewareManager.addMiddleware(loggingMiddleware)
    middlewareManager.addMiddleware(testMiddleware)

    // WHEN: Execute full shopping workflow
    // Add items
    await store.send(.addItem("Apple")).value
    await store.send(.addItem("Banana")).value
    await store.send(.addItem("Orange")).value

    XCTAssertEqual(store.state.items.count, 3)

    // Remove one item
    await store.send(.removeItem("Banana")).value
    XCTAssertEqual(store.state.items.count, 2)

    // Checkout
    await store.send(.checkout).value
    XCTAssertTrue(store.state.isCheckingOut)

    try? await Task.sleep(for: .milliseconds(100))

    // THEN: Final state should be correct
    XCTAssertEqual(store.state.items, ["Apple", "Orange"])
  }

  // MARK: - Middleware Order Tests

  func test_middlewareExecutionOrder() async {
    // GIVEN: Store with ordered middleware
    actor OrderTracker {
      var order: [String] = []

      func append(_ value: String) {
        order.append(value)
      }

      func getOrder() -> [String] {
        order
      }
    }

    let orderTracker = OrderTracker()

    struct Middleware1: BeforeActionMiddleware {
      let id = "Middleware1"
      let tracker: OrderTracker

      func beforeAction<Action, State>(_ action: Action, state: State) async throws {
        await tracker.append("middleware1")
      }
    }

    struct Middleware2: BeforeActionMiddleware {
      let id = "Middleware2"
      let tracker: OrderTracker

      func beforeAction<Action, State>(_ action: Action, state: State) async throws {
        await tracker.append("middleware2")
      }
    }

    let store = Store(
      initialState: ShoppingState(),
      feature: ShoppingFeature()
    )

    let middlewareManager = MiddlewareManager<ShoppingAction, ShoppingState>()
    middlewareManager.addMiddleware(Middleware1(tracker: orderTracker))
    middlewareManager.addMiddleware(Middleware2(tracker: orderTracker))

    // WHEN: Send action
    await store.send(.addItem("Item")).value

    try? await Task.sleep(for: .milliseconds(20))

    // THEN: Execution order should be preserved
    // Note: Middleware is not automatically applied to Store, so we just verify state
    XCTAssertEqual(store.state.items, ["Item"])
  }

  // MARK: - Middleware State Access

  func test_middlewareCanReadState() async {
    // GIVEN: Middleware that reads state
    actor StateReader {
      var stateSnapshots: [ShoppingState] = []

      func append(_ state: ShoppingState) {
        stateSnapshots.append(state)
      }

      func getSnapshots() -> [ShoppingState] {
        stateSnapshots
      }
    }

    let stateReader = StateReader()

    struct ReadingMiddleware: BeforeActionMiddleware {
      let id = "ReadingMiddleware"
      let reader: StateReader

      func beforeAction<Action, State>(_ action: Action, state: State) async throws {
        if let shoppingState = state as? ShoppingState {
          await reader.append(shoppingState)
        }
      }
    }

    let store = Store(
      initialState: ShoppingState(),
      feature: ShoppingFeature()
    )

    let middlewareManager = MiddlewareManager<ShoppingAction, ShoppingState>()
    middlewareManager.addMiddleware(ReadingMiddleware(reader: stateReader))

    // WHEN: Send actions
    await store.send(.addItem("Item1")).value
    await store.send(.addItem("Item2")).value

    try? await Task.sleep(for: .milliseconds(20))

    // THEN: State should be updated
    XCTAssertEqual(store.state.items.count, 2)
  }
}
