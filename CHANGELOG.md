# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-10-18

### Added
- Initial release of ViewFeature
- Redux-like unidirectional data flow for SwiftUI
- `Store` for state management with `@Observable` support
- `ActionHandler` with fluent method chaining API
- `ActionProcessor` with middleware pipeline support
- Task management with automatic cleanup
- Error handling with `onError()` middleware
- Logging middleware with configurable log levels
- Comprehensive test suite (280 tests)

### Features
- Clean API without `inout` parameters
  - State is passed as reference type (`State: AnyObject`)
  - Direct state mutation: `state.count += 1`
  - No need for `&` operator or complex workarounds
- Simplified `Store.processAction()` implementation (3 lines)
- Full SwiftUI integration with `@Observable` macro
- Automatic task cancellation and lifecycle management
- Type-safe action and state handling
