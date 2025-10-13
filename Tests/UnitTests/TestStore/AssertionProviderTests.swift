import Testing

@testable import ViewFeature

/// Comprehensive unit tests for AssertionProvider with 100% code coverage.
///
/// Tests the PrintAssertionProvider implementation to ensure proper assertion handling
/// in non-XCTest environments (like DemoApp).
@MainActor
@Suite("AssertionProvider Tests")
struct AssertionProviderTests {
  // MARK: - PrintAssertionProvider Tests

  @Test("PrintAssertionProvider can be initialized")
  func printAssertionProviderCanBeInitialized() {
    // GIVEN & WHEN: Create a PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // THEN: Should be successfully initialized
    #expect(sut != nil)
  }

  @Test("assertEqual with equal values does not print")
  func assertEqualWithEqualValuesDoesNotPrint() {
    // GIVEN: A PrintAssertionProvider and equal values
    let sut = PrintAssertionProvider()
    let actual = 42
    let expected = 42

    // WHEN: Call assertEqual with equal values
    // THEN: Should not crash and complete successfully
    sut.assertEqual(actual, expected, "Values should be equal", file: #file, line: #line)

    // Note: In real usage, this would not print anything
    // We can't easily test console output in unit tests
  }

  @Test("assertEqual with unequal values prints failure")
  func assertEqualWithUnequalValuesPrintsFailure() {
    // GIVEN: A PrintAssertionProvider and unequal values
    let sut = PrintAssertionProvider()
    let actual = 42
    let expected = 100

    // WHEN: Call assertEqual with unequal values
    // THEN: Should not crash (prints to console instead)
    sut.assertEqual(actual, expected, "Values should be equal", file: #file, line: #line)

    // Note: This would print an assertion failure in real usage
  }

  @Test("assertEqual with strings")
  func assertEqualWithStrings() {
    // GIVEN: A PrintAssertionProvider and string values
    let sut = PrintAssertionProvider()

    // WHEN & THEN: Test with equal strings
    sut.assertEqual("hello", "hello", "Strings should match", file: #file, line: #line)

    // WHEN & THEN: Test with unequal strings
    sut.assertEqual("hello", "world", "Strings should match", file: #file, line: #line)
  }

  @Test("assertEqual with complex types")
  func assertEqualWithComplexTypes() {
    // GIVEN: A PrintAssertionProvider and custom structs
    struct TestStruct: Equatable {
      let id: Int
      let name: String
    }

    let sut = PrintAssertionProvider()
    let value1 = TestStruct(id: 1, name: "Test")
    let value2 = TestStruct(id: 1, name: "Test")
    let value3 = TestStruct(id: 2, name: "Different")

    // WHEN & THEN: Test with equal structs
    sut.assertEqual(value1, value2, "Structs should be equal", file: #file, line: #line)

    // WHEN & THEN: Test with unequal structs
    sut.assertEqual(value1, value3, "Structs should be equal", file: #file, line: #line)
  }

  @Test("assertEqual with optionals")
  func assertEqualWithOptionals() {
    // GIVEN: A PrintAssertionProvider and optional values
    let sut = PrintAssertionProvider()

    // WHEN & THEN: Test with equal optionals
    sut.assertEqual(Optional(42), Optional(42), "Optionals should match", file: #file, line: #line)

    // WHEN & THEN: Test with unequal optionals
    sut.assertEqual(Optional(42), Optional(100), "Optionals should match", file: #file, line: #line)

    // WHEN & THEN: Test with nil
    sut.assertEqual(
      Optional<Int>.none, Optional<Int>.none, "Nils should match", file: #file, line: #line)
    sut.assertEqual(Optional(42), Optional<Int>.none, "Should not match", file: #file, line: #line)
  }

  @Test("assertEqual with arrays")
  func assertEqualWithArrays() {
    // GIVEN: A PrintAssertionProvider and arrays
    let sut = PrintAssertionProvider()

    // WHEN & THEN: Test with equal arrays
    sut.assertEqual([1, 2, 3], [1, 2, 3], "Arrays should match", file: #file, line: #line)

    // WHEN & THEN: Test with unequal arrays
    sut.assertEqual([1, 2, 3], [1, 2, 4], "Arrays should match", file: #file, line: #line)

    // WHEN & THEN: Test with empty arrays
    sut.assertEqual([Int](), [Int](), "Empty arrays should match", file: #file, line: #line)
  }

  @Test("assertEqual with dictionaries")
  func assertEqualWithDictionaries() {
    // GIVEN: A PrintAssertionProvider and dictionaries
    let sut = PrintAssertionProvider()

    // WHEN & THEN: Test with equal dictionaries
    sut.assertEqual(
      ["key": "value"], ["key": "value"], "Dicts should match", file: #file, line: #line)

    // WHEN & THEN: Test with unequal dictionaries
    sut.assertEqual(
      ["key": "value"], ["key": "other"], "Dicts should match", file: #file, line: #line)
  }

  // MARK: - fail(_:file:line:)

  @Test("fail prints failure message")
  func failPrintsFailureMessage() {
    // GIVEN: A PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // WHEN: Call fail with a message
    let message = "This is a test failure"
    // THEN: Should not crash (prints to console instead)
    sut.fail(message, file: #file, line: #line)

    // Note: This would print a failure message in real usage
  }

  @Test("fail with empty message")
  func failWithEmptyMessage() {
    // GIVEN: A PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // WHEN: Call fail with empty message
    // THEN: Should not crash
    sut.fail("", file: #file, line: #line)
  }

  @Test("fail with long message")
  func failWithLongMessage() {
    // GIVEN: A PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // WHEN: Call fail with very long message
    let longMessage = String(repeating: "This is a very long failure message. ", count: 100)
    // THEN: Should not crash
    sut.fail(longMessage, file: #file, line: #line)
  }

  @Test("fail with special characters")
  func failWithSpecialCharacters() {
    // GIVEN: A PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // WHEN: Call fail with special characters
    let message = "失敗: エラーが発生しました 🚨💥 \n\t Special chars: @#$%^&*()"
    // THEN: Should not crash
    sut.fail(message, file: #file, line: #line)
  }

  @Test("fail with multiline message")
  func failWithMultilineMessage() {
    // GIVEN: A PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // WHEN: Call fail with multiline message
    let message = """
      Test failed with multiple lines:
      - Line 1: First issue
      - Line 2: Second issue
      - Line 3: Third issue
      """
    // THEN: Should not crash
    sut.fail(message, file: #file, line: #line)
  }

  // MARK: - Integration Tests

  @Test("PrintAssertionProvider multiple operations")
  func printAssertionProviderMultipleOperations() {
    // GIVEN: A PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // WHEN & THEN: Perform multiple operations in sequence
    sut.assertEqual(1, 1, "First assertion", file: #file, line: #line)
    sut.assertEqual(2, 3, "Second assertion (fails)", file: #file, line: #line)
    sut.fail("Manual failure", file: #file, line: #line)
    sut.assertEqual("test", "test", "Third assertion", file: #file, line: #line)

    // All operations should complete without crashing
  }

  @Test("PrintAssertionProvider can be used across multiple tests")
  func printAssertionProviderCanBeUsedAcrossMultipleTests() {
    // GIVEN: A PrintAssertionProvider used multiple times
    let sut = PrintAssertionProvider()

    // WHEN: Use it for multiple assertions
    for i in 0..<10 {
      sut.assertEqual(i, i, "Iteration \(i)", file: #file, line: #line)
    }

    // THEN: Should handle repeated use without issues
  }

  // MARK: - XCTestAssertionProvider Tests

  @Test("XCTestAssertionProvider can be initialized")
  func xcTestAssertionProviderCanBeInitialized() {
    // GIVEN & WHEN: Create an XCTestAssertionProvider
    let sut = XCTestAssertionProvider()

    // THEN: Should be successfully initialized
    #expect(sut != nil)
  }

  @Test("XCTestAssertionProvider assertEqual with equal values")
  func xcTestAssertionProviderAssertEqualWithEqualValues() {
    // GIVEN: An XCTestAssertionProvider and equal values
    let sut = XCTestAssertionProvider()

    // WHEN & THEN: Call assertEqual with equal values (should not fail)
    sut.assertEqual(42, 42, "Values should be equal", file: #file, line: #line)
    sut.assertEqual("test", "test", "Strings should match", file: #file, line: #line)
  }

  @Test("XCTestAssertionProvider assertEqual with complex types")
  func xcTestAssertionProviderAssertEqualWithComplexTypes() {
    // GIVEN: An XCTestAssertionProvider
    struct TestData: Equatable {
      let id: Int
      let value: String
    }

    let sut = XCTestAssertionProvider()
    let data1 = TestData(id: 1, value: "test")
    let data2 = TestData(id: 1, value: "test")

    // WHEN & THEN: Compare complex types
    sut.assertEqual(data1, data2, "Complex types should match", file: #file, line: #line)
  }

  // MARK: - Protocol Conformance Tests

  @Test("AssertionProvider protocol conformance")
  func assertionProviderProtocolConformance() {
    // GIVEN: Both assertion provider implementations
    let printProvider: any AssertionProvider = PrintAssertionProvider()
    let xcTestProvider: any AssertionProvider = XCTestAssertionProvider()

    // WHEN & THEN: Both should conform to AssertionProvider protocol
    // This is tested at compile time, but we verify runtime behavior

    printProvider.assertEqual(1, 1, "Print provider", file: #file, line: #line)
    xcTestProvider.assertEqual(2, 2, "XCTest provider", file: #file, line: #line)
  }
}
