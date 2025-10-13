import XCTest

@testable import ViewFeature

/// Performance tests for Store and related components.
///
/// Tests throughput, latency, and resource usage under load.
@MainActor
final class StorePerformanceTests: XCTestCase {
  // MARK: - Test Fixtures

  enum PerformanceAction: Sendable {
    case increment
    case batchIncrement(Int)
    case heavyComputation
    case lightTask
  }

  struct PerformanceState: Equatable, Sendable {
    var counter: Int = 0
    var operations: Int = 0
  }

  struct PerformanceFeature: StoreFeature, Sendable {
    typealias Action = PerformanceAction
    typealias State = PerformanceState

    func handle() -> ActionHandler<Action, State> {
      ActionHandler { action, state in
        switch action {
        case .increment:
          state.counter += 1
          state.operations += 1
          return .none

        case .batchIncrement(let count):
          state.counter += count
          state.operations += 1
          return .none

        case .heavyComputation:
          state.operations += 1
          return .run(id: "heavy") {
            // Simulate heavy work
            try await Task.sleep(for: .milliseconds(5))
          }

        case .lightTask:
          state.operations += 1
          return .run(id: "light-\(state.operations)") {
            try await Task.sleep(for: .milliseconds(1))
          }
        }
      }
    }
  }

  // MARK: - Throughput Tests

  func test_highVolumeActionProcessing() async {
    // GIVEN: Store
    let sut = Store(
      initialState: PerformanceState(),
      feature: PerformanceFeature()
    )

    // WHEN: Process many actions
    let actionCount = 1000
    let startTime = Date()

    for _ in 0..<actionCount {
      await sut.send(.increment).value
    }

    let duration = Date().timeIntervalSince(startTime)

    // THEN: Should process efficiently
    XCTAssertEqual(sut.state.counter, actionCount)
    XCTAssertLessThan(
      duration, 5.0, "Processing \(actionCount) actions took too long: \(duration)s")

    let throughput = Double(actionCount) / duration
    print("Throughput: \(Int(throughput)) actions/second")
  }

  func test_batchOperationPerformance() async {
    // GIVEN: Store
    let sut = Store(
      initialState: PerformanceState(),
      feature: PerformanceFeature()
    )

    // WHEN: Batch operations
    let batchSize = 100
    let batchCount = 100
    let startTime = Date()

    for _ in 0..<batchCount {
      await sut.send(.batchIncrement(batchSize)).value
    }

    let duration = Date().timeIntervalSince(startTime)

    // THEN: Should be faster than individual operations
    XCTAssertEqual(sut.state.counter, batchSize * batchCount)
    XCTAssertLessThan(duration, 2.0, "Batch processing took too long: \(duration)s")
  }

  // MARK: - Concurrent Action Tests

  func test_concurrentActionPerformance() async {
    // GIVEN: Store
    let sut = Store(
      initialState: PerformanceState(),
      feature: PerformanceFeature()
    )

    // WHEN: Send many actions concurrently
    let actionCount = 500
    let startTime = Date()

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<actionCount {
        group.addTask {
          await sut.send(.increment).value
        }
      }
    }

    let duration = Date().timeIntervalSince(startTime)

    // THEN: All actions should be processed
    XCTAssertEqual(sut.state.counter, actionCount)
    XCTAssertLessThan(duration, 10.0, "Concurrent processing took too long: \(duration)s")

    print("Concurrent processing: \(Int(Double(actionCount) / duration)) actions/second")
  }

  // MARK: - Task Management Performance

  func test_manyLightTasksPerformance() async {
    // GIVEN: Store
    let sut = Store(
      initialState: PerformanceState(),
      feature: PerformanceFeature()
    )

    // WHEN: Create many light tasks
    let taskCount = 100
    let startTime = Date()

    for _ in 0..<taskCount {
      _ = sut.send(.lightTask)
    }

    // Wait for all tasks to complete
    try? await Task.sleep(for: .milliseconds(500))

    let duration = Date().timeIntervalSince(startTime)

    // THEN: Should handle tasks efficiently
    XCTAssertEqual(sut.state.operations, taskCount)
    XCTAssertLessThan(duration, 5.0, "Light task processing took too long: \(duration)s")
  }

  func test_taskCancellationPerformance() async {
    // GIVEN: Store with many running tasks
    let sut = Store(
      initialState: PerformanceState(),
      feature: PerformanceFeature()
    )

    // Start many tasks
    for _ in 0..<100 {
      _ = sut.send(.heavyComputation)
    }

    try? await Task.sleep(for: .milliseconds(10))

    // WHEN: Cancel all tasks
    let startTime = Date()
    sut.cancelAllTasks()
    try? await Task.sleep(for: .milliseconds(50))
    let duration = Date().timeIntervalSince(startTime)

    // THEN: Cancellation should be fast
    XCTAssertLessThan(duration, 1.0, "Task cancellation took too long: \(duration)s")
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  // MARK: - Memory Performance Tests

  func test_memoryUsageUnderLoad() async {
    // GIVEN: Store
    let sut = Store(
      initialState: PerformanceState(),
      feature: PerformanceFeature()
    )

    // WHEN: Process many actions
    for _ in 0..<10_000 {
      await sut.send(.increment).value
    }

    // THEN: Memory should not grow unbounded
    XCTAssertEqual(sut.state.counter, 10_000)
    // Note: Actual memory testing would require more sophisticated tooling
  }

  // MARK: - State Update Performance

  func test_rapidStateUpdates() async {
    // GIVEN: Store with complex state
    struct ComplexState: Equatable, Sendable {
      var array: [Int] = []
      var dict: [String: Int] = [:]
      var counter: Int = 0
    }

    enum ComplexAction: Sendable {
      case addToArray(Int)
      case addToDict(String, Int)
      case increment
    }

    struct ComplexFeature: StoreFeature, Sendable {
      typealias Action = ComplexAction
      typealias State = ComplexState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
          switch action {
          case .addToArray(let value):
            state.array.append(value)
            return .none
          case .addToDict(let key, let value):
            state.dict[key] = value
            return .none
          case .increment:
            state.counter += 1
            return .none
          }
        }
      }
    }

    let sut = Store(
      initialState: ComplexState(),
      feature: ComplexFeature()
    )

    // WHEN: Perform many state updates
    let startTime = Date()

    for i in 0..<1000 {
      await sut.send(.addToArray(i)).value
      await sut.send(.addToDict("key\(i)", i)).value
      await sut.send(.increment).value
    }

    let duration = Date().timeIntervalSince(startTime)

    // THEN: Updates should be efficient
    XCTAssertEqual(sut.state.array.count, 1000)
    XCTAssertEqual(sut.state.dict.count, 1000)
    XCTAssertEqual(sut.state.counter, 1000)
    XCTAssertLessThan(duration, 5.0, "State updates took too long: \(duration)s")
  }

  // MARK: - XCTest Performance Measurements

  func test_measureActionProcessing() async {
    // GIVEN: Store
    let sut = Store(
      initialState: PerformanceState(),
      feature: PerformanceFeature()
    )

    // WHEN: Measure action processing
    // Note: XCTestCase.measure doesn't work well with async/await
    // Using manual measurement instead
    let iterations = 5
    var durations: [TimeInterval] = []

    for _ in 0..<iterations {
      let start = Date()
      for _ in 0..<100 {
        await sut.send(.increment).value
      }
      let duration = Date().timeIntervalSince(start)
      durations.append(duration)
    }

    let avgDuration = durations.reduce(0, +) / Double(durations.count)

    // THEN: Baseline established
    XCTAssertLessThan(avgDuration, 1.0, "Average processing time too long: \(avgDuration)s")
  }

  func test_measureStateAccess() async {
    // GIVEN: Store with data
    let sut = Store(
      initialState: PerformanceState(counter: 1000),
      feature: PerformanceFeature()
    )

    // WHEN: Measure state access (manual measurement for MainActor compatibility)
    let iterations = 10
    var durations: [TimeInterval] = []

    for _ in 0..<iterations {
      let start = Date()
      var sum = 0
      for _ in 0..<10_000 {
        sum += sut.state.counter
      }
      let duration = Date().timeIntervalSince(start)
      durations.append(duration)
      XCTAssertGreaterThan(sum, 0)
    }

    let avgDuration = durations.reduce(0, +) / Double(durations.count)

    // THEN: State access should be fast
    XCTAssertLessThan(avgDuration, 0.1, "Average state access time too long: \(avgDuration)s")
    print("State access performance: \(String(format: "%.6f", avgDuration))s average")
  }

  // MARK: - Scalability Tests

  func test_scalabilityWithMultipleStores() async {
    // GIVEN: Multiple stores
    let storeCount = 10
    var stores: [Store<PerformanceFeature>] = []

    for _ in 0..<storeCount {
      stores.append(
        Store(
          initialState: PerformanceState(),
          feature: PerformanceFeature()
        ))
    }

    // WHEN: Process actions across all stores
    let startTime = Date()

    for store in stores {
      for _ in 0..<100 {
        await store.send(.increment).value
      }
    }

    let duration = Date().timeIntervalSince(startTime)

    // THEN: All stores should process correctly
    for store in stores {
      XCTAssertEqual(store.state.counter, 100)
    }
    XCTAssertLessThan(duration, 5.0, "Multiple store processing took too long: \(duration)s")
  }

  // MARK: - Real-World Scenario Tests

  func test_realisticWorkloadPerformance() async {
    // GIVEN: Store
    let sut = Store(
      initialState: PerformanceState(),
      feature: PerformanceFeature()
    )

    // WHEN: Simulate realistic workload
    // 80% simple actions, 20% with tasks
    let startTime = Date()

    for i in 0..<500 {
      if i % 5 == 0 {
        _ = sut.send(.heavyComputation)
      } else {
        await sut.send(.increment).value
      }
    }

    // Wait for tasks
    try? await Task.sleep(for: .milliseconds(1000))

    let duration = Date().timeIntervalSince(startTime)

    // THEN: Should handle mixed workload efficiently
    XCTAssertGreaterThanOrEqual(sut.state.operations, 500)
    XCTAssertLessThan(duration, 10.0, "Realistic workload took too long: \(duration)s")

    print("Realistic workload completed in \(String(format: "%.2f", duration))s")
  }

  // MARK: - Stress Tests

  func test_extremeLoadStressTest() async {
    // GIVEN: Store
    let sut = Store(
      initialState: PerformanceState(),
      feature: PerformanceFeature()
    )

    // WHEN: Apply extreme load
    let actionCount = 5000
    let startTime = Date()

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<actionCount {
        group.addTask {
          await sut.send(.increment).value
        }
      }
    }

    let duration = Date().timeIntervalSince(startTime)

    // THEN: System should remain stable
    XCTAssertEqual(sut.state.counter, actionCount)
    print("Extreme load test: \(actionCount) actions in \(String(format: "%.2f", duration))s")
  }
}
