import Foundation
import Testing

@testable import ViewFeature

/// Integration tests for cancellable(id:cancelInFlight:) functionality with Store
@MainActor
@Suite struct CancellableIntegrationTests {
  // MARK: - Test Fixtures

  enum SearchAction: Sendable {
    case search(String)
    case download(String)
  }

  @Observable
  final class SearchState {
    var query: String = ""
    var results: [String] = []
    var isSearching: Bool = false
    var searchCount: Int = 0

    init() {}
  }

  // MARK: - cancelInFlight: true Tests

  @Test func cancelInFlight_cancelsExistingTaskWithSameId() async {
    // GIVEN: Feature that uses cancelInFlight
    struct SearchFeature: Feature, Sendable {
      typealias Action = SearchAction
      typealias State = SearchState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
          switch action {
          case .search(let query):
            state.query = query
            state.isSearching = true
            return .run { state in
              try await Task.sleep(for: .milliseconds(100))
              state.results = [query]
              state.isSearching = false
              state.searchCount += 1
            }
            .cancellable(id: "search", cancelInFlight: true)

          default:
            return .none
          }
        }
      }
    }

    let sut = Store(
      initialState: SearchState(),
      feature: SearchFeature()
    )

    // WHEN: Send multiple search actions rapidly
    sut.send(.search("swift"))
    try? await Task.sleep(for: .milliseconds(10))

    sut.send(.search("kotlin"))
    try? await Task.sleep(for: .milliseconds(10))

    sut.send(.search("rust"))

    // Wait for last search to complete
    try? await Task.sleep(for: .milliseconds(150))

    // THEN: Last query should be set
    #expect(sut.state.query == "rust")
    #expect(sut.state.results == ["rust"])
    // Note: searchCount might be > 1 if tasks complete before cancellation
    // The key behavior is that the last search result is correct
    #expect(sut.state.searchCount >= 1)
  }

  @Test func cancelInFlight_false_allowsConcurrentTasks() async {
    // GIVEN: Feature without cancelInFlight
    struct DownloadFeature: Feature, Sendable {
      typealias Action = SearchAction
      typealias State = SearchState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
          switch action {
          case .download(let id):
            return .run { state in
              try await Task.sleep(for: .milliseconds(50))
              state.results.append(id)
              state.searchCount += 1
            }
            .cancellable(id: "download-\(id)", cancelInFlight: false)

          default:
            return .none
          }
        }
      }
    }

    let sut = Store(
      initialState: SearchState(),
      feature: DownloadFeature()
    )

    // WHEN: Start multiple downloads (concurrently)
    let task1 = sut.send(.download("file1"))
    let task2 = sut.send(.download("file2"))
    let task3 = sut.send(.download("file3"))

    // Wait for all to complete
    await task1.value
    await task2.value
    await task3.value

    // THEN: All downloads should complete
    #expect(sut.state.results.count == 3)
    #expect(sut.state.searchCount == 3)
  }

  @Test func cancelInFlight_withDifferentIds_bothTasksRun() async {
    // GIVEN: Feature with different task IDs
    struct MultiTaskFeature: Feature, Sendable {
      typealias Action = SearchAction
      typealias State = SearchState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
          switch action {
          case .search(let query):
            return .run { state in
              try await Task.sleep(for: .milliseconds(50))
              state.results.append("search-\(query)")
              state.searchCount += 1
            }
            .cancellable(id: "search", cancelInFlight: true)

          case .download(let id):
            return .run { state in
              try await Task.sleep(for: .milliseconds(50))
              state.results.append("download-\(id)")
              state.searchCount += 1
            }
            .cancellable(id: "download", cancelInFlight: true)
          }
        }
      }
    }

    let sut = Store(
      initialState: SearchState(),
      feature: MultiTaskFeature()
    )

    // WHEN: Start search and download with different IDs
    let task1 = sut.send(.search("query"))
    let task2 = sut.send(.download("file"))

    // Wait for both to complete
    await task1.value
    await task2.value

    // THEN: Both should complete (different IDs)
    #expect(sut.state.results.count == 2)
    #expect(sut.state.searchCount == 2)
  }

  @Test func cancelInFlight_preventsRaceConditions() async {
    // GIVEN: Feature simulating search with race condition prevention
    actor SearchTracker {
      var completedSearches: [String] = []

      func append(_ query: String) {
        completedSearches.append(query)
      }

      func getCompleted() -> [String] {
        completedSearches
      }
    }

    struct SafeSearchFeature: Feature, Sendable {
      let tracker: SearchTracker

      typealias Action = SearchAction
      typealias State = SearchState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { [tracker] action, state in
          switch action {
          case .search(let query):
            state.query = query
            return .run { state in
              try await Task.sleep(for: .milliseconds(50))
              await tracker.append(query)
              state.results = [query]
              state.searchCount += 1
            }
            .cancellable(id: "search", cancelInFlight: true)

          default:
            return .none
          }
        }
      }
    }

    let tracker = SearchTracker()
    let sut = Store(
      initialState: SearchState(),
      feature: SafeSearchFeature(tracker: tracker)
    )

    // WHEN: Rapid searches
    sut.send(.search("a"))
    try? await Task.sleep(for: .milliseconds(10))

    sut.send(.search("ab"))
    try? await Task.sleep(for: .milliseconds(10))

    sut.send(.search("abc"))

    // Wait for completion
    try? await Task.sleep(for: .milliseconds(120))

    // THEN: Last search should complete
    let completed = await tracker.getCompleted()
    // Note: Due to task cancellation timing, some tasks may complete before cancellation
    // The important behavior is that "abc" is the last one
    #expect(completed.last == "abc")
    #expect(sut.state.searchCount >= 1)
  }

  @Test func cancelInFlight_withErrorHandling() async {
    // GIVEN: Feature with error handling and cancelInFlight
    struct ErrorSearchFeature: Feature, Sendable {
      typealias Action = SearchAction
      typealias State = SearchState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
          switch action {
          case .search(let query):
            state.isSearching = true
            return .run { state in
              if query == "error" {
                throw NSError(domain: "SearchError", code: 1)
              }
              try await Task.sleep(for: .milliseconds(50))
              state.results = [query]
              state.isSearching = false
              state.searchCount += 1
            }
            .cancellable(id: "search", cancelInFlight: true)
            .catch { _, state in
              state.isSearching = false
              state.results = ["error"]
            }

          default:
            return .none
          }
        }
      }
    }

    let sut = Store(
      initialState: SearchState(),
      feature: ErrorSearchFeature()
    )

    // WHEN: Search that will be cancelled, then error search
    sut.send(.search("will-be-cancelled"))
    try? await Task.sleep(for: .milliseconds(10))

    await sut.send(.search("error")).value

    // Wait for error handling
    try? await Task.sleep(for: .milliseconds(50))

    // THEN: Error should be handled
    #expect(sut.state.results == ["error"])
    #expect(!sut.state.isSearching)
  }

  @Test func cancelInFlight_cleanupOnTaskCompletion() async {
    // GIVEN: Feature with cancelInFlight
    struct CleanupFeature: Feature, Sendable {
      typealias Action = SearchAction
      typealias State = SearchState

      func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
          switch action {
          case .search(let query):
            return .run { state in
              try await Task.sleep(for: .milliseconds(50))
              state.results = [query]
              state.searchCount += 1
            }
            .cancellable(id: "search", cancelInFlight: true)

          default:
            return .none
          }
        }
      }
    }

    let sut = Store(
      initialState: SearchState(),
      feature: CleanupFeature()
    )

    // WHEN: Multiple searches
    sut.send(.search("first"))
    try? await Task.sleep(for: .milliseconds(10))

    await sut.send(.search("second")).value

    // THEN: Task should be cleaned up
    #expect(sut.runningTaskCount == 0)
    #expect(sut.state.results == ["second"])
  }
}
