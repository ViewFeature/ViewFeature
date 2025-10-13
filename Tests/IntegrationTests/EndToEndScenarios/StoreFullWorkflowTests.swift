import XCTest

@testable import ViewFeature

/// End-to-end tests for complete Store workflows.
///
/// Tests full user scenarios where Store, ActionHandler, Middleware, and TaskManager
/// work together to handle complex application flows.
@MainActor
final class StoreFullWorkflowTests: XCTestCase {
  // MARK: - Test Fixtures

  enum UserAction: Sendable {
    case loadUser(String)
    case updateProfile(name: String, email: String)
    case logout
    case refreshData
    case cancelLoad
  }

  struct UserState: Equatable, Sendable {
    var userId: String?
    var userName: String?
    var userEmail: String?
    var isLoading: Bool = false
    var isLoggedIn: Bool = false
    var errorMessage: String?
    var refreshCount: Int = 0
  }

  struct UserFeature: StoreFeature, Sendable {
    typealias Action = UserAction
    typealias State = UserState

    func handle() -> ActionHandler<Action, State> {
      ActionHandler { action, state in
        switch action {
        case .loadUser(let id):
          state.isLoading = true
          state.userId = id
          return .run(id: "loadUser") {
            // Simulate network request
            try await Task.sleep(for: .milliseconds(50))
          }

        case .updateProfile(let name, let email):
          state.userName = name
          state.userEmail = email
          state.isLoggedIn = true
          state.isLoading = false
          return .none

        case .logout:
          state = UserState()
          return .cancel(id: "loadUser")

        case .refreshData:
          state.refreshCount += 1
          return .run(id: "refresh") {
            try await Task.sleep(for: .milliseconds(20))
          }

        case .cancelLoad:
          state.isLoading = false
          return .cancel(id: "loadUser")
        }
      }
    }
  }

  // MARK: - Login Workflow Tests

  func test_fullLoginWorkflow() async {
    // GIVEN: Store with initial state
    let sut = Store(
      initialState: UserState(),
      feature: UserFeature()
    )

    // WHEN: Execute full login workflow
    // Step 1: Load user
    await sut.send(.loadUser("user123")).value
    XCTAssertTrue(sut.state.isLoading)
    XCTAssertEqual(sut.state.userId, "user123")

    // Step 2: Update profile
    await sut.send(.updateProfile(name: "John Doe", email: "john@example.com")).value
    XCTAssertEqual(sut.state.userName, "John Doe")
    XCTAssertEqual(sut.state.userEmail, "john@example.com")
    XCTAssertTrue(sut.state.isLoggedIn)
    XCTAssertFalse(sut.state.isLoading)

    // THEN: User should be fully logged in
    XCTAssertEqual(sut.state.userId, "user123")
    XCTAssertTrue(sut.state.isLoggedIn)
  }

  func test_logoutCancelsOngoingLoad() async {
    // GIVEN: Store with ongoing load
    let sut = Store(
      initialState: UserState(),
      feature: UserFeature()
    )

    // Start loading user
    _ = sut.send(.loadUser("user456"))
    try? await Task.sleep(for: .milliseconds(10))
    XCTAssertTrue(sut.state.isLoading)

    // WHEN: Logout while loading
    await sut.send(.logout).value

    // THEN: State should be reset and task cancelled
    XCTAssertFalse(sut.state.isLoading)
    XCTAssertFalse(sut.state.isLoggedIn)
    XCTAssertNil(sut.state.userId)
    XCTAssertNil(sut.state.userName)
  }

  // MARK: - Multi-Action Workflows

  func test_multipleSequentialActions() async {
    // GIVEN: Store
    let sut = Store(
      initialState: UserState(),
      feature: UserFeature()
    )

    // WHEN: Execute multiple sequential actions
    await sut.send(.loadUser("user789")).value
    await sut.send(.updateProfile(name: "Jane Doe", email: "jane@example.com")).value
    await sut.send(.refreshData).value

    // Wait for refresh to complete
    try? await Task.sleep(for: .milliseconds(50))

    await sut.send(.refreshData).value
    try? await Task.sleep(for: .milliseconds(50))

    // THEN: All actions should be processed
    XCTAssertEqual(sut.state.userId, "user789")
    XCTAssertEqual(sut.state.userName, "Jane Doe")
    XCTAssertEqual(sut.state.refreshCount, 2)
    XCTAssertTrue(sut.state.isLoggedIn)
  }

  func test_complexStateTransitions() async {
    // GIVEN: Store
    let sut = Store(
      initialState: UserState(),
      feature: UserFeature()
    )

    // WHEN: Execute complex state transitions
    // Load -> Cancel -> Load -> Update -> Refresh -> Logout
    await sut.send(.loadUser("user1")).value
    try? await Task.sleep(for: .milliseconds(10))

    await sut.send(.cancelLoad).value
    XCTAssertFalse(sut.state.isLoading)

    await sut.send(.loadUser("user2")).value
    await sut.send(.updateProfile(name: "User 2", email: "user2@example.com")).value
    await sut.send(.refreshData).value
    try? await Task.sleep(for: .milliseconds(50))

    await sut.send(.logout).value

    // THEN: Should end in clean state
    XCTAssertFalse(sut.state.isLoggedIn)
    XCTAssertNil(sut.state.userId)
  }

  // MARK: - Concurrent Actions

  func test_concurrentActionProcessing() async {
    // GIVEN: Store
    let sut = Store(
      initialState: UserState(),
      feature: UserFeature()
    )

    // WHEN: Send multiple actions concurrently
    let task1 = sut.send(.loadUser("user1"))
    let task2 = sut.send(.updateProfile(name: "Test", email: "test@example.com"))
    let task3 = sut.send(.refreshData)

    await task1.value
    await task2.value
    await task3.value

    // Wait for async tasks
    try? await Task.sleep(for: .milliseconds(100))

    // THEN: All actions should be processed
    XCTAssertEqual(sut.state.userName, "Test")
    XCTAssertTrue(sut.state.isLoggedIn)
    XCTAssertGreaterThanOrEqual(sut.state.refreshCount, 1)
  }

  // MARK: - Task Cancellation Workflows

  func test_multipleCancellations() async {
    // GIVEN: Store with multiple running tasks
    let sut = Store(
      initialState: UserState(),
      feature: UserFeature()
    )

    // WHEN: Start multiple tasks and cancel them
    _ = sut.send(.loadUser("user1"))
    _ = sut.send(.refreshData)
    try? await Task.sleep(for: .milliseconds(10))

    sut.cancelAllTasks()
    try? await Task.sleep(for: .milliseconds(100))

    // THEN: All tasks should be cancelled
    XCTAssertEqual(sut.runningTaskCount, 0)
  }

  // MARK: - Data Refresh Workflows

  func test_repeatedRefreshes() async {
    // GIVEN: Store
    let sut = Store(
      initialState: UserState(),
      feature: UserFeature()
    )

    // WHEN: Perform multiple refreshes
    for _ in 0..<5 {
      await sut.send(.refreshData).value
      try? await Task.sleep(for: .milliseconds(30))
    }

    // THEN: All refreshes should be counted
    XCTAssertEqual(sut.state.refreshCount, 5)
  }

  // MARK: - State Consistency Tests

  func test_stateConsistencyDuringWorkflow() async {
    // GIVEN: Store
    let sut = Store(
      initialState: UserState(),
      feature: UserFeature()
    )

    // WHEN: Execute workflow and check consistency at each step
    await sut.send(.loadUser("user123")).value
    XCTAssertTrue(sut.state.isLoading)
    XCTAssertNil(sut.state.userName)  // Should be nil before update

    await sut.send(.updateProfile(name: "Test User", email: "test@example.com")).value
    XCTAssertFalse(sut.state.isLoading)
    XCTAssertNotNil(sut.state.userName)
    XCTAssertTrue(sut.state.isLoggedIn)

    let userId = sut.state.userId
    let userName = sut.state.userName

    await sut.send(.refreshData).value

    // THEN: User data should remain consistent after refresh
    XCTAssertEqual(sut.state.userId, userId)
    XCTAssertEqual(sut.state.userName, userName)
  }
}
