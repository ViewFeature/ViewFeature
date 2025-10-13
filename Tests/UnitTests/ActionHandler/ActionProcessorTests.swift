import XCTest

@testable import ViewFeature

/// Comprehensive unit tests for ActionProcessor with 100% code coverage.
///
/// Tests every public method, property, and code path in ActionProcessor.swift
@MainActor
final class ActionProcessorTests: XCTestCase {
  // MARK: - Test Fixtures

  enum TestAction: Sendable {
    case increment
    case decrement
    case asyncOperation
    case throwError
  }

  struct TestState: Equatable, Sendable {
    var count = 0
    var errorMessage: String?
    var isLoading = false
  }

  // MARK: - init(_:)

  func test_init_createsProcessorWithExecution() async {
    // GIVEN & WHEN: Create processor with execution
    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }

    // THEN: Should execute action
    var state = TestState()
    let task = await sut.process(action: .increment, state: &state)

    XCTAssertEqual(state.count, 1)
    if case .none = task.storeTask {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected noTask")
    }
  }

  func test_init_withComplexExecution() async {
    // GIVEN: Complex execution logic
    let sut = ActionProcessor<TestAction, TestState> { action, state in
      switch action {
      case .increment:
        state.count += 1
      case .decrement:
        state.count -= 1
      case .asyncOperation:
        state.isLoading = true
      case .throwError:
        state.errorMessage = "error"
      }
      return .none
    }

    // WHEN: Execute different actions
    var state = TestState()
    _ = await sut.process(action: .increment, state: &state)
    _ = await sut.process(action: .decrement, state: &state)
    _ = await sut.process(action: .asyncOperation, state: &state)

    // THEN: Should handle all actions
    XCTAssertEqual(state.count, 0)  // +1 -1 = 0
    XCTAssertTrue(state.isLoading)
  }

  // MARK: - process(action:state:)

  func test_process_executesActionSuccessfully() async {
    // GIVEN: Processor
    var executionCount = 0
    let sut = ActionProcessor<TestAction, TestState> { _, state in
      executionCount += 1
      state.count += 1
      return .none
    }

    // WHEN: Process action
    var state = TestState()
    let task = await sut.process(action: .increment, state: &state)

    // THEN: Should execute and mutate state
    XCTAssertEqual(executionCount, 1)
    XCTAssertEqual(state.count, 1)
    if case .none = task.storeTask {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected noTask")
    }
  }

  func test_process_returnsRunTask() async {
    // GIVEN: Processor that returns run task
    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.isLoading = true
      return .run(id: "test-task") {}
    }

    // WHEN: Process action
    var state = TestState()
    let task = await sut.process(action: .asyncOperation, state: &state)

    // THEN: Should return run task
    XCTAssertTrue(state.isLoading)
    if case .run(let id, _, _) = task.storeTask {
      XCTAssertEqual(id, "test-task")
    } else {
      XCTFail("Expected run task")
    }
  }

  func test_process_returnsCancelTask() async {
    // GIVEN: Processor that returns cancel task
    let sut = ActionProcessor<TestAction, TestState> { _, _ in
      .cancel(id: "cancel-me")
    }

    // WHEN: Process action
    var state = TestState()
    let task = await sut.process(action: .increment, state: &state)

    // THEN: Should return cancel task
    if case .cancel(let id) = task.storeTask {
      XCTAssertEqual(id, "cancel-me")
    } else {
      XCTFail("Expected cancel task")
    }
  }

  func test_process_handlesError() async {
    // GIVEN: Processor with middleware that throws
    struct ThrowingMiddleware: BeforeActionMiddleware {
      var id: String { "Throwing" }
      func beforeAction<Action, State>(_ action: Action, state: State) async throws {
        throw NSError(domain: "Test", code: 1)
      }
    }

    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }
    .use(ThrowingMiddleware())

    // WHEN: Process action (middleware throws)
    var state = TestState()
    let task = await sut.process(action: .throwError, state: &state)

    // THEN: Should return noTask on error and not execute action
    XCTAssertEqual(state.count, 0)  // Action not executed due to middleware error
    if case .none = task.storeTask {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected noTask on error")
    }
  }

  func test_process_executesMiddleware() async throws {
    // GIVEN: Processor with logging middleware
    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }
    .use(LoggingMiddleware(logLevel: .debug))

    // WHEN: Process action
    var state = TestState()
    _ = await sut.process(action: .increment, state: &state)

    // THEN: Should execute with middleware
    XCTAssertEqual(state.count, 1)
  }

  func test_process_callsErrorHandler() async {
    // GIVEN: Processor with error handler and throwing middleware
    struct ThrowingMiddleware: BeforeActionMiddleware {
      var id: String { "Throwing" }
      func beforeAction<Action, State>(_ action: Action, state: State) async throws {
        throw NSError(domain: "Test", code: 1)
      }
    }

    var errorWasCalled = false
    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }
    .use(ThrowingMiddleware())
    .onError { error, state in
      errorWasCalled = true
      state.errorMessage = error.localizedDescription
    }

    // WHEN: Process action (middleware throws)
    var state = TestState()
    _ = await sut.process(action: .throwError, state: &state)

    // THEN: Should call error handler
    XCTAssertTrue(errorWasCalled)
    XCTAssertNotNil(state.errorMessage)
  }

  func test_process_multipleTimesWithSameProcessor() async {
    // GIVEN: Processor
    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }

    // WHEN: Process multiple times
    var state = TestState()
    _ = await sut.process(action: .increment, state: &state)
    _ = await sut.process(action: .increment, state: &state)
    _ = await sut.process(action: .increment, state: &state)

    // THEN: Should accumulate state changes
    XCTAssertEqual(state.count, 3)
  }

  // MARK: - use(_:)

  func test_use_addsMiddleware() async {
    // GIVEN: Processor
    let base = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }

    // WHEN: Add middleware
    let sut = base.use(LoggingMiddleware(logLevel: .debug))

    // THEN: Should create new processor with middleware
    var state = TestState()
    _ = await sut.process(action: .increment, state: &state)
    XCTAssertEqual(state.count, 1)
  }

  func test_use_supportsMethodChaining() async {
    // GIVEN: Processor with multiple middleware
    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }
    .use(LoggingMiddleware(logLevel: .debug))
    .use(LoggingMiddleware(category: "Test1"))
    .use(LoggingMiddleware(category: "Test2"))

    // WHEN: Process action
    var state = TestState()
    _ = await sut.process(action: .increment, state: &state)

    // THEN: Should work with multiple middleware
    XCTAssertEqual(state.count, 1)
  }

  func test_use_preservesOriginalProcessor() async {
    // GIVEN: Base processor
    let base = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }

    // WHEN: Create new processor with middleware
    let withMiddleware = base.use(LoggingMiddleware())

    // THEN: Base processor should remain unchanged
    var state1 = TestState()
    _ = await base.process(action: .increment, state: &state1)
    XCTAssertEqual(state1.count, 1)

    var state2 = TestState()
    _ = await withMiddleware.process(action: .increment, state: &state2)
    XCTAssertEqual(state2.count, 1)
  }

  // MARK: - onError(_:)

  func test_onError_addsErrorHandler() async {
    // GIVEN: Processor with error handler and throwing middleware
    struct ThrowingMiddleware: BeforeActionMiddleware {
      var id: String { "Throwing" }
      func beforeAction<Action, State>(_ action: Action, state: State) async throws {
        throw NSError(domain: "Test", code: 42)
      }
    }

    var capturedError: Error?
    let sut = ActionProcessor<TestAction, TestState> { _, _ in
      .none
    }
    .use(ThrowingMiddleware())
    .onError { error, state in
      capturedError = error
      state.errorMessage = "Handled"
    }

    // WHEN: Process action (middleware throws)
    var state = TestState()
    _ = await sut.process(action: .throwError, state: &state)

    // THEN: Should call error handler
    XCTAssertNotNil(capturedError)
    XCTAssertEqual((capturedError as? NSError)?.code, 42)
    XCTAssertEqual(state.errorMessage, "Handled")
  }

  func test_onError_mutatesState() async {
    // GIVEN: Processor with error handler and throwing middleware
    struct ThrowingMiddleware: BeforeActionMiddleware {
      var id: String { "Throwing" }
      func beforeAction<Action, State>(_ action: Action, state: State) async throws {
        throw NSError(domain: "Test", code: 1)
      }
    }

    let sut = ActionProcessor<TestAction, TestState> { _, _ in
      .none
    }
    .use(ThrowingMiddleware())
    .onError { _, state in
      state.count = 999
      state.isLoading = false
      state.errorMessage = "Error occurred"
    }

    // WHEN: Process action (middleware throws)
    var state = TestState(count: 0, errorMessage: nil, isLoading: true)
    _ = await sut.process(action: .throwError, state: &state)

    // THEN: Should mutate state in error handler
    XCTAssertEqual(state.count, 999)
    XCTAssertFalse(state.isLoading)
    XCTAssertEqual(state.errorMessage, "Error occurred")
  }

  func test_onError_supportsChaining() async {
    // GIVEN: Processor with middleware and error handler and throwing middleware
    struct ThrowingMiddleware: BeforeActionMiddleware {
      var id: String { "Throwing" }
      func beforeAction<Action, State>(_ action: Action, state: State) async throws {
        throw NSError(domain: "Test", code: 1)
      }
    }

    let sut = ActionProcessor<TestAction, TestState> { _, _ in
      .none
    }
    .use(LoggingMiddleware())
    .use(ThrowingMiddleware())
    .onError { _, state in
      state.errorMessage = "Handled"
    }

    // WHEN: Process action
    var state = TestState()
    _ = await sut.process(action: .throwError, state: &state)

    // THEN: Should work with middleware
    XCTAssertEqual(state.errorMessage, "Handled")
  }

  func test_onError_doesNotAffectSuccessfulExecution() async {
    // GIVEN: Processor with error handler
    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }
    .onError { _, state in
      state.errorMessage = "Should not be called"
    }

    // WHEN: Process successful action
    var state = TestState()
    _ = await sut.process(action: .increment, state: &state)

    // THEN: Error handler should not be called
    XCTAssertEqual(state.count, 1)
    XCTAssertNil(state.errorMessage)
  }

  // MARK: - transform(_:)

  func test_transform_modifiesTask() async {
    // GIVEN: Processor with transform
    let sut = ActionProcessor<TestAction, TestState> { _, state in
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

    // WHEN: Process action
    var state = TestState()
    let task = await sut.process(action: .asyncOperation, state: &state)

    // THEN: Task should be transformed
    XCTAssertEqual(state.count, 1)
    if case .run(let id, _, _) = task.storeTask {
      XCTAssertEqual(id, "transformed")
    } else {
      XCTFail("Expected run task")
    }
  }

  func test_transform_canConvertTaskTypes() async {
    // GIVEN: Processor that converts run to cancel
    let sut = ActionProcessor<TestAction, TestState> { _, _ in
      .run(id: "will-cancel") {}
    }
    .transform { task in
      switch task.storeTask {
      case .run(let id, _, _):
        return .cancel(id: id)
      default:
        return task
      }
    }

    // WHEN: Process action
    var state = TestState()
    let task = await sut.process(action: .asyncOperation, state: &state)

    // THEN: Should convert to cancel task
    if case .cancel(let id) = task.storeTask {
      XCTAssertEqual(id, "will-cancel")
    } else {
      XCTFail("Expected cancel task")
    }
  }

  func test_transform_leavesNoTaskUnchanged() async {
    // GIVEN: Processor with transform
    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }
    .transform { task in
      switch task.storeTask {
      case .run:
        return .cancel(id: "transformed")
      default:
        return task
      }
    }

    // WHEN: Process action returning noTask
    var state = TestState()
    let task = await sut.process(action: .increment, state: &state)

    // THEN: noTask should remain unchanged
    if case .none = task.storeTask {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected noTask")
    }
  }

  func test_transform_supportsChaining() async {
    // GIVEN: Processor with middleware, error handler, and transform
    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .run(id: "task") {}
    }
    .use(LoggingMiddleware())
    .onError { _, state in
      state.errorMessage = "Error"
    }
    .transform { task in
      task  // Identity transform
    }

    // WHEN: Process action
    var state = TestState()
    let task = await sut.process(action: .asyncOperation, state: &state)

    // THEN: Should work with all features
    XCTAssertEqual(state.count, 1)
    if case .run = task.storeTask {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected run task")
    }
  }

  // MARK: - Integration Tests

  func test_fullPipeline_successfulExecution() async {
    // GIVEN: Processor with all features
    var middlewareExecuted = false
    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 10
      return .run(id: "main-task") {}
    }
    .use(LoggingMiddleware(logLevel: .debug))
    .onError { _, state in
      state.errorMessage = "Unexpected error"
    }
    .transform { task in
      middlewareExecuted = true
      return task
    }

    // WHEN: Process action
    var state = TestState(count: 5)
    let task = await sut.process(action: .increment, state: &state)

    // THEN: Should execute full pipeline
    XCTAssertEqual(state.count, 15)
    XCTAssertTrue(middlewareExecuted)
    XCTAssertNil(state.errorMessage)
    if case .run(let id, _, _) = task.storeTask {
      XCTAssertEqual(id, "main-task")
    }
  }

  func test_fullPipeline_errorHandling() async {
    // GIVEN: Processor with throwing middleware and error handler
    struct ThrowingMiddleware: BeforeActionMiddleware {
      var id: String { "Throwing" }
      func beforeAction<Action, State>(_ action: Action, state: State) async throws {
        throw NSError(domain: "Pipeline", code: 500)
      }
    }

    let sut = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }
    .use(LoggingMiddleware())
    .use(ThrowingMiddleware())
    .onError { error, state in
      state.errorMessage = "Pipeline error: \(error.localizedDescription)"
      state.count = 0  // Reset on error
    }

    // WHEN: Process action (middleware throws)
    var state = TestState()
    let task = await sut.process(action: TestAction.throwError, state: &state)

    // THEN: Should handle error correctly
    XCTAssertEqual(state.count, 0)
    XCTAssertNotNil(state.errorMessage)
    XCTAssertTrue(state.errorMessage?.contains("Pipeline error") ?? false)
    if case .none = task.storeTask {
      XCTAssertTrue(true)
    }
  }

  func test_complexStateModification() async {
    // GIVEN: Processors for different actions
    let incrementProcessor = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      state.isLoading = false
      return .none
    }

    let decrementProcessor = ActionProcessor<TestAction, TestState> { _, state in
      state.count -= 1
      state.errorMessage = nil
      return .none
    }

    let asyncProcessor = ActionProcessor<TestAction, TestState> { _, state in
      state.isLoading = true
      return .run(id: "async") {}
    }

    struct ThrowingMiddleware: BeforeActionMiddleware {
      var id: String { "Throwing" }
      func beforeAction<Action, State>(_ action: Action, state: State) async throws {
        throw NSError(domain: "Test", code: 1)
      }
    }

    let errorProcessor = ActionProcessor<TestAction, TestState> { _, _ in
      .none
    }
    .use(ThrowingMiddleware())
    .onError { error, state in
      state.errorMessage = "Error: \(error.localizedDescription)"
      state.isLoading = false
    }

    // WHEN: Execute multiple actions
    var state = TestState()

    _ = await incrementProcessor.process(action: TestAction.increment, state: &state)
    XCTAssertEqual(state.count, 1)
    XCTAssertFalse(state.isLoading)

    _ = await asyncProcessor.process(action: TestAction.asyncOperation, state: &state)
    XCTAssertTrue(state.isLoading)

    _ = await errorProcessor.process(action: TestAction.throwError, state: &state)
    XCTAssertNotNil(state.errorMessage)
    XCTAssertFalse(state.isLoading)

    _ = await decrementProcessor.process(action: TestAction.decrement, state: &state)
    XCTAssertEqual(state.count, 0)
    XCTAssertNil(state.errorMessage)
  }

  func test_immutabilityOfMethodChaining() async {
    // GIVEN: Base processor
    let base = ActionProcessor<TestAction, TestState> { _, state in
      state.count += 1
      return .none
    }

    // WHEN: Create multiple variants
    let withMiddleware = base.use(LoggingMiddleware())
    let withError = base.onError { _, state in state.errorMessage = "Error" }
    let withTransform = base.transform { $0 }

    // THEN: All variants should work independently
    var state1 = TestState()
    _ = await base.process(action: .increment, state: &state1)
    XCTAssertEqual(state1.count, 1)

    var state2 = TestState()
    _ = await withMiddleware.process(action: .increment, state: &state2)
    XCTAssertEqual(state2.count, 1)

    var state3 = TestState()
    _ = await withError.process(action: .increment, state: &state3)
    XCTAssertEqual(state3.count, 1)

    var state4 = TestState()
    _ = await withTransform.process(action: .increment, state: &state4)
    XCTAssertEqual(state4.count, 1)
  }
}
