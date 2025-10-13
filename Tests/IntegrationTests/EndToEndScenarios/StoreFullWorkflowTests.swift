import Foundation
import Testing

@testable import ViewFeature

/// End-to-end tests for complete Store workflows.
///
/// Tests full user scenarios where Store, ActionHandler, Middleware, and TaskManager
/// work together to handle complex application flows.
@MainActor
@Suite struct StoreFullWorkflowTests {
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

  @Test func fullLoginWorkflow() async {
    // GIVEN: Store with initial state
    let sut = Store(
      initialState: UserState(),
      feature: UserFeature()
    )

    // WHEN: Execute full login workflow
    // Step 1: Load user
    await sut.send(.loadUser("user123")).value
    #expect(sut.state.isLoading)
    #expect(sut.state.userId == "user123")

    // Step 2: Update profile
    await sut.send(.updateProfile(name: "John Doe", email: "john@example.com")).value
    #expect(sut.state.userName == "John Doe")
    #expect(sut.state.userEmail == "john@example.com")
    #expect(sut.state.isLoggedIn)
    #expect(!sut.state.isLoading)

    // THEN: User should be fully logged in
    #expect(sut.state.userId == "user123")
    #expect(sut.state.isLoggedIn)
  }

  @Test func logoutCancelsOngoingLoad() async {
    // GIVEN: Store with ongoing load
    let sut = Store(
      initialState: UserState(),
      feature: UserFeature()
    )

    // Start loading user
    _ = sut.send(.loadUser("user456"))
    try? await Task.sleep(for: .milliseconds(10))
    #expect(sut.state.isLoading)

    // WHEN: Logout while loading
    await sut.send(.logout).value

    // THEN: State should be reset and task cancelled
    #expect(!sut.state.isLoading)
    #expect(!sut.state.isLoggedIn)
    #expect(sut.state.userId == nil)
    #expect(sut.state.userName == nil)
  }

  // MARK: - Multi-Action Workflows

  @Test func multipleSequentialActions() async {
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
    #expect(sut.state.userId == "user789")
    #expect(sut.state.userName == "Jane Doe")
    #expect(sut.state.refreshCount == 2)
    #expect(sut.state.isLoggedIn)
  }

  @Test func complexStateTransitions() async {
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
    #expect(!sut.state.isLoading)

    await sut.send(.loadUser("user2")).value
    await sut.send(.updateProfile(name: "User 2", email: "user2@example.com")).value
    await sut.send(.refreshData).value
    try? await Task.sleep(for: .milliseconds(50))

    await sut.send(.logout).value

    // THEN: Should end in clean state
    #expect(!sut.state.isLoggedIn)
    #expect(sut.state.userId == nil)
  }

  // MARK: - Concurrent Actions

  @Test func concurrentActionProcessing() async {
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
    #expect(sut.state.userName == "Test")
    #expect(sut.state.isLoggedIn)
    #expect(sut.state.refreshCount >= 1)
  }

  // MARK: - Task Cancellation Workflows

  @Test func multipleCancellations() async {
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
    #expect(sut.runningTaskCount == 0)
  }

  // MARK: - Data Refresh Workflows

  @Test func repeatedRefreshes() async {
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
    #expect(sut.state.refreshCount == 5)
  }

  // MARK: - State Consistency Tests

  @Test func stateConsistencyDuringWorkflow() async {
    // GIVEN: Store
    let sut = Store(
      initialState: UserState(),
      feature: UserFeature()
    )

    // WHEN: Execute workflow and check consistency at each step
    await sut.send(.loadUser("user123")).value
    #expect(sut.state.isLoading)
    #expect(sut.state.userName == nil)  // Should be nil before update

    await sut.send(.updateProfile(name: "Test User", email: "test@example.com")).value
    #expect(!sut.state.isLoading)
    #expect(sut.state.userName != nil)
    #expect(sut.state.isLoggedIn)

    let userId = sut.state.userId
    let userName = sut.state.userName

    await sut.send(.refreshData).value

    // THEN: User data should remain consistent after refresh
    #expect(sut.state.userId == userId)
    #expect(sut.state.userName == userName)
  }
}
