# ``ViewFeature``

Modern state management for Swift 6.2 with async/await and automatic MainActor isolation.

## Overview

ViewFeature is a lightweight, type-safe state management library built specifically for Swift 6.2 and SwiftUI. It embraces modern Swift concurrency while providing a unidirectional data flow architecture inspired by Redux and The Composable Architecture.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:DesignDecisions>

### Core Components

- ``Store``
- ``Feature``
- ``ActionHandler``
- ``ActionTask``

### Task Management

- ``TaskManager``
- ``TaskID``

### Middleware

- ``ActionMiddleware``
- ``LoggingMiddleware``
- ``BeforeActionMiddleware``
- ``AfterActionMiddleware``
- ``ErrorHandlingMiddleware``
