import XCTest

@testable import ViewFeature

/// Integration tests for Store and ActionHandler interaction.
///
/// Tests how Store and ActionHandler work together to process actions
/// and manage state transitions.
@MainActor
final class StoreActionHandlerIntegrationTests: XCTestCase {
  // MARK: - Test Fixtures

  enum TodoAction: Sendable {
    case add(String)
    case complete(Int)
    case delete(Int)
    case toggleAll
    case clearCompleted
  }

  struct Todo: Equatable, Sendable {
    let id: Int
    var title: String
    var isCompleted: Bool
  }

  struct TodoState: Equatable, Sendable {
    var todos: [Todo] = []
    var nextId: Int = 1
  }

  struct TodoFeature: StoreFeature, Sendable {
    typealias Action = TodoAction
    typealias State = TodoState

    func handle() -> ActionHandler<Action, State> {
      ActionHandler { action, state in
        switch action {
        case .add(let title):
          let todo = Todo(id: state.nextId, title: title, isCompleted: false)
          state.todos.append(todo)
          state.nextId += 1
          return .none

        case .complete(let id):
          if let index = state.todos.firstIndex(where: { $0.id == id }) {
            state.todos[index].isCompleted = true
          }
          return .none

        case .delete(let id):
          state.todos.removeAll { $0.id == id }
          return .none

        case .toggleAll:
          let allCompleted = state.todos.allSatisfy(\.isCompleted)
          for index in state.todos.indices {
            state.todos[index].isCompleted = !allCompleted
          }
          return .none

        case .clearCompleted:
          state.todos.removeAll { $0.isCompleted }
          return .none
        }
      }
    }
  }

  // MARK: - Basic Integration Tests

  func test_storeAndHandlerProcessSimpleAction() async {
    // GIVEN: Store with TodoFeature
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    // WHEN: Send add action
    await sut.send(.add("Buy milk")).value

    // THEN: State should be updated
    XCTAssertEqual(sut.state.todos.count, 1)
    XCTAssertEqual(sut.state.todos[0].title, "Buy milk")
    XCTAssertEqual(sut.state.todos[0].id, 1)
    XCTAssertFalse(sut.state.todos[0].isCompleted)
  }

  func test_storeAndHandlerProcessMultipleActions() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    // WHEN: Send multiple add actions
    await sut.send(.add("Task 1")).value
    await sut.send(.add("Task 2")).value
    await sut.send(.add("Task 3")).value

    // THEN: All tasks should be added
    XCTAssertEqual(sut.state.todos.count, 3)
    XCTAssertEqual(sut.state.todos[0].title, "Task 1")
    XCTAssertEqual(sut.state.todos[1].title, "Task 2")
    XCTAssertEqual(sut.state.todos[2].title, "Task 3")
  }

  // MARK: - State Mutation Tests

  func test_handlerMutatesStateCorrectly() async {
    // GIVEN: Store with todos
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    await sut.send(.add("Task 1")).value
    await sut.send(.add("Task 2")).value

    // WHEN: Complete a task
    await sut.send(.complete(1)).value

    // THEN: Task should be marked completed
    XCTAssertTrue(sut.state.todos[0].isCompleted)
    XCTAssertFalse(sut.state.todos[1].isCompleted)
  }

  func test_handlerDeletesCorrectly() async {
    // GIVEN: Store with multiple todos
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    await sut.send(.add("Task 1")).value
    await sut.send(.add("Task 2")).value
    await sut.send(.add("Task 3")).value

    // WHEN: Delete middle task
    await sut.send(.delete(2)).value

    // THEN: Task 2 should be removed
    XCTAssertEqual(sut.state.todos.count, 2)
    XCTAssertEqual(sut.state.todos[0].title, "Task 1")
    XCTAssertEqual(sut.state.todos[1].title, "Task 3")
  }

  // MARK: - Complex State Transitions

  func test_toggleAllWithMixedCompletionStates() async {
    // GIVEN: Store with mixed completion states
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    await sut.send(.add("Task 1")).value
    await sut.send(.add("Task 2")).value
    await sut.send(.add("Task 3")).value
    await sut.send(.complete(1)).value

    // WHEN: Toggle all
    await sut.send(.toggleAll).value

    // THEN: All should be completed (not all were completed before)
    XCTAssertTrue(sut.state.todos.allSatisfy(\.isCompleted))

    // WHEN: Toggle all again
    await sut.send(.toggleAll).value

    // THEN: All should be uncompleted
    XCTAssertTrue(sut.state.todos.allSatisfy { !$0.isCompleted })
  }

  func test_clearCompletedRemovesOnlyCompletedTasks() async {
    // GIVEN: Store with mixed completion states
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    await sut.send(.add("Task 1")).value
    await sut.send(.add("Task 2")).value
    await sut.send(.add("Task 3")).value
    await sut.send(.complete(1)).value
    await sut.send(.complete(3)).value

    // WHEN: Clear completed
    await sut.send(.clearCompleted).value

    // THEN: Only uncompleted task should remain
    XCTAssertEqual(sut.state.todos.count, 1)
    XCTAssertEqual(sut.state.todos[0].title, "Task 2")
    XCTAssertFalse(sut.state.todos[0].isCompleted)
  }

  // MARK: - Action Handler Workflow Tests

  func test_complexTodoWorkflow() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    // WHEN: Execute complex workflow
    // Add tasks
    await sut.send(.add("Task 1")).value
    await sut.send(.add("Task 2")).value
    await sut.send(.add("Task 3")).value
    await sut.send(.add("Task 4")).value

    // Complete some
    await sut.send(.complete(1)).value
    await sut.send(.complete(2)).value

    // Delete one
    await sut.send(.delete(3)).value

    // Clear completed
    await sut.send(.clearCompleted).value

    // THEN: Only uncompleted task should remain
    XCTAssertEqual(sut.state.todos.count, 1)
    XCTAssertEqual(sut.state.todos[0].title, "Task 4")
    XCTAssertFalse(sut.state.todos[0].isCompleted)
  }

  // MARK: - ID Generation Tests

  func test_idGenerationIsSequential() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    // WHEN: Add multiple todos
    await sut.send(.add("Task 1")).value
    await sut.send(.add("Task 2")).value
    await sut.send(.add("Task 3")).value

    // THEN: IDs should be sequential
    XCTAssertEqual(sut.state.todos[0].id, 1)
    XCTAssertEqual(sut.state.todos[1].id, 2)
    XCTAssertEqual(sut.state.todos[2].id, 3)
    XCTAssertEqual(sut.state.nextId, 4)
  }

  func test_idGenerationAfterDeletion() async {
    // GIVEN: Store with todos
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    await sut.send(.add("Task 1")).value
    await sut.send(.add("Task 2")).value
    await sut.send(.delete(1)).value

    // WHEN: Add new task
    await sut.send(.add("Task 3")).value

    // THEN: ID should continue from last nextId
    XCTAssertEqual(sut.state.todos.count, 2)
    XCTAssertEqual(sut.state.todos[1].id, 3)
  }

  // MARK: - State Consistency Tests

  func test_stateRemainsConsistentAcrossActions() async {
    // GIVEN: Store
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    // WHEN: Execute multiple actions
    await sut.send(.add("Task 1")).value
    let countAfterAdd = sut.state.todos.count
    XCTAssertEqual(countAfterAdd, 1)

    await sut.send(.complete(1)).value
    let countAfterComplete = sut.state.todos.count
    XCTAssertEqual(countAfterComplete, 1)  // Count should remain same

    await sut.send(.add("Task 2")).value
    let countAfterSecondAdd = sut.state.todos.count
    XCTAssertEqual(countAfterSecondAdd, 2)

    await sut.send(.clearCompleted).value
    let finalCount = sut.state.todos.count

    // THEN: State should be consistent
    XCTAssertEqual(finalCount, 1)
    XCTAssertEqual(sut.state.todos[0].title, "Task 2")
  }

  // MARK: - Edge Cases

  func test_deleteNonexistentTask() async {
    // GIVEN: Store with one task
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    await sut.send(.add("Task 1")).value

    // WHEN: Delete nonexistent task
    await sut.send(.delete(999)).value

    // THEN: No tasks should be deleted
    XCTAssertEqual(sut.state.todos.count, 1)
  }

  func test_completeNonexistentTask() async {
    // GIVEN: Store with one task
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    await sut.send(.add("Task 1")).value

    // WHEN: Complete nonexistent task
    await sut.send(.complete(999)).value

    // THEN: No tasks should be affected
    XCTAssertFalse(sut.state.todos[0].isCompleted)
  }

  func test_toggleAllWithEmptyList() async {
    // GIVEN: Store with no tasks
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    // WHEN: Toggle all on empty list
    await sut.send(.toggleAll).value

    // THEN: Should not crash
    XCTAssertEqual(sut.state.todos.count, 0)
  }

  func test_clearCompletedWithNoCompletedTasks() async {
    // GIVEN: Store with uncompleted tasks
    let sut = Store(
      initialState: TodoState(),
      feature: TodoFeature()
    )

    await sut.send(.add("Task 1")).value
    await sut.send(.add("Task 2")).value

    // WHEN: Clear completed
    await sut.send(.clearCompleted).value

    // THEN: No tasks should be removed
    XCTAssertEqual(sut.state.todos.count, 2)
  }
}
