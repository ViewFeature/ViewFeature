import Foundation

/// Protocol for providing assertion capabilities to TestStore
///
/// This allows TestStore to work both with XCTest (in test targets)
/// and without XCTest (in app targets like DemoApp).
public protocol AssertionProvider {
  /// Assert that two values are equal
  func assertEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String,
    file: StaticString,
    line: UInt
  )

  /// Fail with a message
  func fail(
    _ message: String,
    file: StaticString,
    line: UInt
  )
}

/// Print-based assertion provider for use in app targets
///
/// This provider prints assertion failures instead of using XCTest,
/// making it suitable for DemoApp and other non-test targets.
public struct PrintAssertionProvider: AssertionProvider {
  public init() {}

  public func assertEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String,
    file: StaticString,
    line: UInt
  ) {
    if actual != expected {
      print("❌ Assertion failed at \(file):\(line)")
      print("   \(message)")
      print("   Expected: \(expected)")
      print("   Actual: \(actual)")
    }
  }

  public func fail(
    _ message: String,
    file: StaticString,
    line: UInt
  ) {
    print("❌ Test failed at \(file):\(line)")
    print("   \(message)")
  }
}
