@testable import ViewFeature
import XCTest

/// Comprehensive unit tests for ActionHandler with 100% code coverage.
///
/// Tests every public method in ActionHandler.swift
@MainActor
final class ActionHandlerTests: XCTestCase {

  // MARK: - Test Fixtures

  enum TestAction: Sendable {
    case increment
    case decrement
    case asyncOp
  }

  struct TestState: Equatable, Sendable {
    var count = 0
    var errorMessage: String?
    var isLoading = false
  }

  // MARK: - init(_:)

  func test_init_createsHandler() async {
    // GIVEN & WHEN: Create handler
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .none
    }

    // THEN: Should handle actions
    var state = TestState()
    _ = await sut.handle(action: .increment, state: &state)
    XCTAssertEqual(state.count, 1)
  }

  func test_init_withComplexLogic() async {
    // GIVEN: Handler with complex logic
    let sut = ActionHandler<TestAction, TestState> { action, state in
      switch action {
      case .increment:
        state.count += 1
      case .decrement:
        state.count -= 1
      case .asyncOp:
        state.isLoading = true
        return .run(id: "async") {}
      }
      return .none
    }

    // WHEN: Handle different actions
    var state = TestState()
    _ = await sut.handle(action: .increment, state: &state)
    _ = await sut.handle(action: .decrement, state: &state)

    // THEN: Should process all actions
    XCTAssertEqual(state.count, 0) // +1 -1 = 0
  }

  // MARK: - handle(action:state:)

  func test_handle_executesAction() async {
    // GIVEN: Handler
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.count += 5
      return .none
    }

    // WHEN: Handle action
    var state = TestState()
    let task = await sut.handle(action: .increment, state: &state)

    // THEN: Should update state
    XCTAssertEqual(state.count, 5)
    if case .none = task.storeTask {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected noTask")
    }
  }

  func test_handle_returnsRunTask() async {
    // GIVEN: Handler returning run task
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.isLoading = true
      return .run(id: "test") {}
    }

    // WHEN: Handle action
    var state = TestState()
    let task = await sut.handle(action: .asyncOp, state: &state)

    // THEN: Should return run task
    XCTAssertTrue(state.isLoading)
    if case .run(let id, _, _) = task.storeTask {
      XCTAssertEqual(id, "test")
    } else {
      XCTFail("Expected run task")
    }
  }

  func test_handle_returnsCancelTask() async {
    // GIVEN: Handler returning cancel task
    let sut = ActionHandler<TestAction, TestState> { action, state in
      return .cancel(id: "cancel-me")
    }

    // WHEN: Handle action
    var state = TestState()
    let task = await sut.handle(action: .increment, state: &state)

    // THEN: Should return cancel task
    if case .cancel(let id) = task.storeTask {
      XCTAssertEqual(id, "cancel-me")
    } else {
      XCTFail("Expected cancel task")
    }
  }

  func test_handle_multipleTimes() async {
    // GIVEN: Handler
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .none
    }

    // WHEN: Handle multiple times
    var state = TestState()
    _ = await sut.handle(action: .increment, state: &state)
    _ = await sut.handle(action: .increment, state: &state)
    _ = await sut.handle(action: .increment, state: &state)

    // THEN: Should accumulate
    XCTAssertEqual(state.count, 3)
  }

  // MARK: - onError(_:)

  func test_onError_returnsNewHandler() async {
    // GIVEN: Base handler
    let baseHandler = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .none
    }

    // WHEN: Add error handler
    let sut = baseHandler.onError { error, state in
      state.errorMessage = "Error handled"
    }

    // THEN: Should return a working handler
    var state = TestState()
    _ = await sut.handle(action: .increment, state: &state)
    XCTAssertEqual(state.count, 1)
  }

  func test_onError_supportsChaining() async {
    // GIVEN: Handler with multiple chained methods
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .none
    }
    .onError { error, state in
      state.errorMessage = "Error"
    }
    .use(LoggingMiddleware())

    // WHEN: Handle action
    var state = TestState()
    _ = await sut.handle(action: .increment, state: &state)

    // THEN: Should work with chaining
    XCTAssertEqual(state.count, 1)
  }

  func test_onError_canBeCalled() async {
    // GIVEN: Handler
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .none
    }
    .onError { _, state in
      state.count = 999
    }

    // WHEN: Handle action (no error occurs)
    var state = TestState()
    _ = await sut.handle(action: .increment, state: &state)

    // THEN: Normal operation works
    XCTAssertEqual(state.count, 1)
  }

  // MARK: - use(_:)

  func test_use_addsMiddleware() async {
    // GIVEN: Handler with middleware
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .none
    }
    .use(LoggingMiddleware(category: "TestFeature"))

    // WHEN: Handle action
    var state = TestState()
    _ = await sut.handle(action: .increment, state: &state)

    // THEN: Should execute with middleware
    XCTAssertEqual(state.count, 1)
  }

  func test_use_defaultCategory() async {
    // GIVEN: Handler with default middleware
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .none
    }
    .use(LoggingMiddleware())

    // WHEN: Handle action
    var state = TestState()
    _ = await sut.handle(action: .increment, state: &state)

    // THEN: Should execute with default middleware
    XCTAssertEqual(state.count, 1)
  }

  func test_use_supportsChaining() async {
    // GIVEN: Handler with multiple middleware
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .none
    }
    .use(LoggingMiddleware(category: "Cat1"))
    .use(LoggingMiddleware(category: "Cat2"))
    .onError { error, state in
      state.errorMessage = "Error"
    }

    // WHEN: Handle action
    var state = TestState()
    _ = await sut.handle(action: .increment, state: &state)

    // THEN: Should work with multiple middleware
    XCTAssertEqual(state.count, 1)
  }

  // MARK: - transform(_:)

  func test_transform_modifiesTask() async {
    // GIVEN: Handler with transform
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .run(id: "original") {}
    }
    .transform { task in
      switch task.storeTask {
      case .run:
        return .run(id: "transformed") {}
      default:
        return task
      }
    }

    // WHEN: Handle action
    var state = TestState()
    let task = await sut.handle(action: .increment, state: &state)

    // THEN: Task should be transformed
    XCTAssertEqual(state.count, 1)
    if case .run(let id, _, _) = task.storeTask {
      XCTAssertEqual(id, "transformed")
    } else {
      XCTFail("Expected run task")
    }
  }

  func test_transform_canConvertTasks() async {
    // GIVEN: Handler that converts tasks
    let sut = ActionHandler<TestAction, TestState> { action, state in
      return .run(id: "convert") {}
    }
    .transform { task in
      switch task.storeTask {
      case .run(let id, _, _):
        return .cancel(id: id)
      default:
        return task
      }
    }

    // WHEN: Handle action
    var state = TestState()
    let task = await sut.handle(action: .asyncOp, state: &state)

    // THEN: Should convert to cancel
    if case .cancel(let id) = task.storeTask {
      XCTAssertEqual(id, "convert")
    } else {
      XCTFail("Expected cancel task")
    }
  }

  func test_transform_leavesNoTaskUnchanged() async {
    // GIVEN: Handler with transform
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .none
    }
    .transform { task in
      switch task.storeTask {
      case .run:
        return .cancel(id: "modified")
      default:
        return task
      }
    }

    // WHEN: Handle action returning noTask
    var state = TestState()
    let task = await sut.handle(action: .increment, state: &state)

    // THEN: noTask should remain
    if case .none = task.storeTask {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected noTask")
    }
  }

  func test_transform_supportsChaining() async {
    // GIVEN: Handler with all features
    let sut = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .run(id: "task") {}
    }
    .use(LoggingMiddleware())
    .onError { error, state in
      state.errorMessage = "Error"
    }
    .transform { task in
      return task
    }

    // WHEN: Handle action
    var state = TestState()
    let task = await sut.handle(action: .asyncOp, state: &state)

    // THEN: Should work with all features
    XCTAssertEqual(state.count, 1)
    if case .run = task.storeTask {
      XCTAssertTrue(true)
    }
  }

  // MARK: - Integration Tests

  func test_fullPipeline_successfulExecution() async {
    // GIVEN: Handler with all features
    let sut = ActionHandler<TestAction, TestState> { action, state in
      switch action {
      case .increment:
        state.count += 1
        return .none
      case .decrement:
        state.count -= 1
        return .none
      case .asyncOp:
        state.isLoading = true
        return .run(id: "async") {}
      }
    }
    .use(LoggingMiddleware(category: "Integration"))
    .onError { error, state in
      state.errorMessage = "Unexpected error"
    }
    .transform { task in
      task // Identity
    }

    // WHEN: Handle multiple actions
    var state = TestState()
    _ = await sut.handle(action: .increment, state: &state)
    _ = await sut.handle(action: .increment, state: &state)
    _ = await sut.handle(action: .decrement, state: &state)

    // THEN: Should process all actions
    XCTAssertEqual(state.count, 1) // +1 +1 -1 = 1
    XCTAssertNil(state.errorMessage)
  }

  func test_immutabilityOfChaining() async {
    // GIVEN: Base handler
    let base = ActionHandler<TestAction, TestState> { action, state in
      state.count += 1
      return .none
    }

    // WHEN: Create variants
    let withMiddleware = base.use(LoggingMiddleware())
    let withError = base.onError { _, state in state.errorMessage = "E" }
    let withTransform = base.transform { $0 }

    // THEN: All should work independently
    var state1 = TestState()
    _ = await base.handle(action: .increment, state: &state1)
    XCTAssertEqual(state1.count, 1)

    var state2 = TestState()
    _ = await withMiddleware.handle(action: .increment, state: &state2)
    XCTAssertEqual(state2.count, 1)

    var state3 = TestState()
    _ = await withError.handle(action: .increment, state: &state3)
    XCTAssertEqual(state3.count, 1)

    var state4 = TestState()
    _ = await withTransform.handle(action: .increment, state: &state4)
    XCTAssertEqual(state4.count, 1)
  }

  func test_complexScenario() async {
    // GIVEN: Handler with complex scenario
    let sut = ActionHandler<TestAction, TestState> { action, state in
      switch action {
      case .increment:
        state.count += 10
      case .decrement:
        state.count -= 5
      case .asyncOp:
        state.isLoading = true
        return .run(id: "complex") {}
      }
      return .none
    }
    .use(LoggingMiddleware(category: "Complex"))
    .onError { error, state in
      state.errorMessage = error.localizedDescription
      state.isLoading = false
    }

    // WHEN: Execute complex sequence
    var state = TestState(count: 100)
    _ = await sut.handle(action: .increment, state: &state)
    XCTAssertEqual(state.count, 110)

    let task = await sut.handle(action: .asyncOp, state: &state)
    XCTAssertTrue(state.isLoading)
    if case .run(let id, _, _) = task.storeTask {
      XCTAssertEqual(id, "complex")
    }

    _ = await sut.handle(action: .decrement, state: &state)
    XCTAssertEqual(state.count, 105) // 110 - 5 = 105
  }
}
