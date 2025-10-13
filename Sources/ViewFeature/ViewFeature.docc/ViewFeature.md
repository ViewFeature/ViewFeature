# ``ViewFeature``

A modern, lightweight state management library for Swift applications.

## Overview

ViewFeature is a type-safe state management library built with Swift 6 strict concurrency, designed for seamless SwiftUI integration. It provides a unidirectional data flow architecture inspired by Redux and The Composable Architecture.

### Key Features

- **Modern Swift**: Built with Swift 6, async/await, and strict concurrency
- **Type-Safe**: Leverages Swift's type system for compile-time safety
- **Reactive**: Seamless SwiftUI integration with @Observable
- **SOLID Architecture**: Clean separation of concerns following SOLID principles
- **Flexible Testing**: 3 testing patterns supporting both Equatable and non-Equatable states
- **Lightweight**: Minimal dependencies (only swift-log)
- **Production-Ready**: 267 comprehensive tests with high coverage

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Architecture>
- ``Store``
- ``StoreFeature``

### Action Handling

- ``ActionHandler``
- ``ActionProcessor``
- ``ActionTask``

### Testing

- <doc:TestingGuide>
- ``TestStore``
- ``AssertionProvider``

### Middleware

- ``ActionMiddleware``
- ``LoggingMiddleware``
- ``MiddlewareManager``

### Task Management

- ``TaskManager``
- ``StoreTask``

### Migration

- <doc:MigrationGuide>
