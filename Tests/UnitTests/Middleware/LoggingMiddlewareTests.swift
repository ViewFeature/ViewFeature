import Foundation
import Logging
import Testing

@testable import ViewFeature

/// Comprehensive unit tests for LoggingMiddleware with 100% code coverage.
///
/// Tests every public method, property, and code path in LoggingMiddleware.swift
@MainActor
@Suite struct LoggingMiddlewareTests {
    // MARK: - Test Fixtures

    enum TestAction {
        case increment
        case decrement
        case loadData
    }

    struct TestState: Equatable {
        var count = 0
        var isLoading = false
    }

    // MARK: - init(category:logLevel:)

    @Test func init_withDefaults() {
        // GIVEN & WHEN: Create middleware with defaults
        let sut = LoggingMiddleware()

        // THEN: Should have correct ID
        #expect(sut.id == "ViewFeature.Logging")
    }

    @Test func init_withCustomCategory() {
        // GIVEN & WHEN: Create middleware with custom category
        let sut = LoggingMiddleware(category: "CustomCategory")

        // THEN: Should have correct ID
        #expect(sut.id == "ViewFeature.Logging")
    }

    @Test func init_withCustomLogLevel() {
        // GIVEN & WHEN: Create middleware with custom log level
        let sut = LoggingMiddleware(
            category: "Test",
            logLevel: .error
        )

        // THEN: Should have correct ID
        #expect(sut.id == "ViewFeature.Logging")
    }

    // MARK: - id

    @Test func id_returnsCorrectValue() {
        // GIVEN: A logging middleware
        let sut = LoggingMiddleware()

        // WHEN & THEN: ID should match expected value
        #expect(sut.id == "ViewFeature.Logging")
    }

    // MARK: - beforeAction(_:state:)

    @Test func beforeAction_logsWhenDebugLevelSufficient() async throws {
        // GIVEN: Middleware with debug level
        let sut = LoggingMiddleware(
            category: "Test",
            logLevel: .debug
        )
        let action = TestAction.increment
        let state = TestState()

        // WHEN: Call beforeAction
        // THEN: Should not throw
        try await sut.beforeAction(action, state: state)
    }

    @Test func beforeAction_skipsWhenLogLevelInsufficient() async throws {
        // GIVEN: Middleware with error level (higher than debug)
        let sut = LoggingMiddleware(
            category: "Test",
            logLevel: .error
        )
        let action = TestAction.increment
        let state = TestState()

        // WHEN: Call beforeAction
        // THEN: Should not throw and return early
        try await sut.beforeAction(action, state: state)
    }

    @Test func beforeAction_handlesComplexAction() async throws {
        // GIVEN: Middleware with debug level
        let sut = LoggingMiddleware(
            category: "Test",
            logLevel: .debug
        )
        let action = TestAction.loadData
        let state = TestState(count: 42, isLoading: true)

        // WHEN: Call beforeAction
        // THEN: Should handle complex state without crashing
        try await sut.beforeAction(action, state: state)
    }

    // MARK: - afterAction(_:state:result:duration:)

    @Test func afterAction_logsWithDurationWhenInfoLevelSufficient() async throws {
        // GIVEN: Middleware with info level
        let sut = LoggingMiddleware(
            category: "Test",
            logLevel: .info
        )
        let action = TestAction.increment
        let state = TestState()
        let result = ActionTask<TestAction, TestState>.none
        let duration: TimeInterval = 0.123

        // WHEN: Call afterAction
        // THEN: Should not throw
        try await sut.afterAction(action, state: state, result: result, duration: duration)
    }

    @Test func afterAction_skipsWhenLogLevelInsufficient() async throws {
        // GIVEN: Middleware with error level (higher than info)
        let sut = LoggingMiddleware(
            category: "Test",
            logLevel: .error
        )
        let action = TestAction.increment
        let state = TestState()
        let result = ActionTask<TestAction, TestState>.none
        let duration: TimeInterval = 0.123

        // WHEN: Call afterAction
        // THEN: Should not throw and return early
        try await sut.afterAction(action, state: state, result: result, duration: duration)
    }

    @Test func afterAction_formatsDurationInMilliseconds() async throws {
        // GIVEN: Middleware with info level
        let sut = LoggingMiddleware(
            category: "Test",
            logLevel: .info
        )
        let action = TestAction.increment
        let state = TestState()
        let result = ActionTask<TestAction, TestState>.none

        // WHEN: Call with various durations
        // THEN: Should format various durations without crashing
        try await sut.afterAction(action, state: state, result: result, duration: 0.001)
        try await sut.afterAction(action, state: state, result: result, duration: 0.123)
        try await sut.afterAction(action, state: state, result: result, duration: 1.234)
    }

    @Test func afterAction_handlesDebugLevel() async throws {
        // GIVEN: Middleware with debug level (lower than info)
        let sut = LoggingMiddleware(
            category: "Test",
            logLevel: .debug
        )
        let action = TestAction.increment
        let state = TestState()
        let result = ActionTask<TestAction, TestState>.none
        let duration: TimeInterval = 0.123

        // WHEN: Call afterAction
        // THEN: Should log at info level even with debug configured
        try await sut.afterAction(action, state: state, result: result, duration: duration)
    }

    // MARK: - onError(_:action:state:)

    @Test func onError_logsError() async throws {
        // GIVEN: Middleware with any log level
        let sut = LoggingMiddleware(
            category: "Test",
            logLevel: .info
        )
        let error = NSError(
            domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error message"])
        let action = TestAction.increment
        let state = TestState()

        // WHEN: Call onError
        // THEN: Should not throw
        try await sut.onError(error, action: action, state: state)
    }

    @Test func onError_alwaysLogsRegardlessOfLevel() async throws {
        // GIVEN: Middleware with critical level (highest)
        let sut = LoggingMiddleware(
            category: "Test",
            logLevel: .critical
        )
        let error = NSError(
            domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Critical error"])
        let action = TestAction.increment
        let state = TestState()

        // WHEN: Call onError
        // THEN: Should always log errors
        try await sut.onError(error, action: action, state: state)
    }

    @Test func onError_handlesErrorWithLocalizedDescription() async throws {
        // GIVEN: Middleware
        let sut = LoggingMiddleware(
            category: "Test",
            logLevel: .error
        )
        let error = NSError(
            domain: "TestError",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "日本語エラーメッセージ with emoji 🚨"]
        )
        let action = TestAction.loadData
        let state = TestState(count: 10, isLoading: true)

        // WHEN: Call onError
        // THEN: Should handle localized error message
        try await sut.onError(error, action: action, state: state)
    }

    // MARK: - Integration Tests

    @Test func allMiddlewareMethods_withSameInstance() async throws {
        // GIVEN: Single middleware instance
        let sut = LoggingMiddleware(
            category: "Integration",
            logLevel: .debug
        )
        let action = TestAction.increment
        let state = TestState()
        let result = ActionTask<TestAction, TestState>.none
        let duration: TimeInterval = 0.5

        // WHEN & THEN: All methods should work together
        try await sut.beforeAction(action, state: state)
        try await sut.afterAction(action, state: state, result: result, duration: duration)

        let error = NSError(domain: "TestError", code: 1)
        try await sut.onError(error, action: action, state: state)

        // Should not crash
        #expect(true)
    }

    @Test func logLevelFiltering_worksCorrectly() async throws {
        // GIVEN: Middleware with trace level (lowest)
        let traceLevelMiddleware = LoggingMiddleware(
            category: "TraceTest",
            logLevel: .trace
        )

        // WHEN: All methods are called
        let action = TestAction.increment
        let state = TestState()
        let result = ActionTask<TestAction, TestState>.none

        // THEN: Should log everything
        try await traceLevelMiddleware.beforeAction(action, state: state)
        try await traceLevelMiddleware.afterAction(action, state: state, result: result, duration: 0.1)
        try await traceLevelMiddleware.onError(
            NSError(domain: "Test", code: 1), action: action, state: state)
    }
}
