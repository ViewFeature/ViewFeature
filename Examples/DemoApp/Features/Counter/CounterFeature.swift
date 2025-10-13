import Foundation
import Observation
import ViewFeature

struct CounterFeature: StoreFeature {
    // MARK: - State

    @Observable
    final class State {
        var count: Int = 0
        var isLoading: Bool = false

        init(count: Int = 0, isLoading: Bool = false) {
            self.count = count
            self.isLoading = isLoading
        }
    }

    // MARK: - Action

    enum Action: Sendable {
        case increment
        case decrement
        case reset
        case delayedIncrement
        case cancelDelayedIncrement
        case finishLoading
    }

    // MARK: - Handler

    func handle() -> ActionHandler<Action, State> {
        ActionHandler { action, state in
            switch action {
            case .increment:
                state.count += 1
                return .none

            case .decrement:
                state.count -= 1
                return .none

            case .reset:
                state.count = 0
                return .none

            case .delayedIncrement:
                state.isLoading = true
                state.count += 1
                return .run(id: "delayed-increment") {
                    try await Task.sleep(for: .seconds(3))
                    // Task completes - View layer handles follow-up actions if needed
                }
                .catch { _, state in
                    state.isLoading = false
                }

            case .cancelDelayedIncrement:
                state.isLoading = false
                return .cancel(id: "delayed-increment")

            case .finishLoading:
                state.isLoading = false
                return .none
            }
        }
    }
}
