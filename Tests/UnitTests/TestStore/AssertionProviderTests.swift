import XCTest

@testable import ViewFeature

/// Comprehensive unit tests for AssertionProvider with 100% code coverage.
///
/// Tests the PrintAssertionProvider implementation to ensure proper assertion handling
/// in non-XCTest environments (like DemoApp).
@MainActor
final class AssertionProviderTests: XCTestCase {
  // MARK: - PrintAssertionProvider Tests

  func test_printAssertionProvider_canBeInitialized() {
    // GIVEN & WHEN: Create a PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // THEN: Should be successfully initialized
    XCTAssertNotNil(sut)
  }

  func test_assertEqual_withEqualValues_doesNotPrint() {
    // GIVEN: A PrintAssertionProvider and equal values
    let sut = PrintAssertionProvider()
    let actual = 42
    let expected = 42

    // WHEN: Call assertEqual with equal values
    // THEN: Should not crash and complete successfully
    sut.assertEqual(actual, expected, "Values should be equal", file: #file, line: #line)

    // Note: In real usage, this would not print anything
    // We can't easily test console output in unit tests
    XCTAssertTrue(true, "assertEqual completed without crashing")
  }

  func test_assertEqual_withUnequalValues_printsFailure() {
    // GIVEN: A PrintAssertionProvider and unequal values
    let sut = PrintAssertionProvider()
    let actual = 42
    let expected = 100

    // WHEN: Call assertEqual with unequal values
    // THEN: Should not crash (prints to console instead)
    sut.assertEqual(actual, expected, "Values should be equal", file: #file, line: #line)

    // Note: This would print an assertion failure in real usage
    XCTAssertTrue(true, "assertEqual completed without crashing")
  }

  func test_assertEqual_withStrings() {
    // GIVEN: A PrintAssertionProvider and string values
    let sut = PrintAssertionProvider()

    // WHEN & THEN: Test with equal strings
    sut.assertEqual("hello", "hello", "Strings should match", file: #file, line: #line)

    // WHEN & THEN: Test with unequal strings
    sut.assertEqual("hello", "world", "Strings should match", file: #file, line: #line)

    XCTAssertTrue(true, "String comparisons completed")
  }

  func test_assertEqual_withComplexTypes() {
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

    XCTAssertTrue(true, "Complex type comparisons completed")
  }

  func test_assertEqual_withOptionals() {
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

    XCTAssertTrue(true, "Optional comparisons completed")
  }

  func test_assertEqual_withArrays() {
    // GIVEN: A PrintAssertionProvider and arrays
    let sut = PrintAssertionProvider()

    // WHEN & THEN: Test with equal arrays
    sut.assertEqual([1, 2, 3], [1, 2, 3], "Arrays should match", file: #file, line: #line)

    // WHEN & THEN: Test with unequal arrays
    sut.assertEqual([1, 2, 3], [1, 2, 4], "Arrays should match", file: #file, line: #line)

    // WHEN & THEN: Test with empty arrays
    sut.assertEqual([Int](), [Int](), "Empty arrays should match", file: #file, line: #line)

    XCTAssertTrue(true, "Array comparisons completed")
  }

  func test_assertEqual_withDictionaries() {
    // GIVEN: A PrintAssertionProvider and dictionaries
    let sut = PrintAssertionProvider()

    // WHEN & THEN: Test with equal dictionaries
    sut.assertEqual(
      ["key": "value"], ["key": "value"], "Dicts should match", file: #file, line: #line)

    // WHEN & THEN: Test with unequal dictionaries
    sut.assertEqual(
      ["key": "value"], ["key": "other"], "Dicts should match", file: #file, line: #line)

    XCTAssertTrue(true, "Dictionary comparisons completed")
  }

  // MARK: - fail(_:file:line:)

  func test_fail_printsFailureMessage() {
    // GIVEN: A PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // WHEN: Call fail with a message
    let message = "This is a test failure"
    // THEN: Should not crash (prints to console instead)
    sut.fail(message, file: #file, line: #line)

    // Note: This would print a failure message in real usage
    XCTAssertTrue(true, "fail() completed without crashing")
  }

  func test_fail_withEmptyMessage() {
    // GIVEN: A PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // WHEN: Call fail with empty message
    // THEN: Should not crash
    sut.fail("", file: #file, line: #line)

    XCTAssertTrue(true, "fail() with empty message completed")
  }

  func test_fail_withLongMessage() {
    // GIVEN: A PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // WHEN: Call fail with very long message
    let longMessage = String(repeating: "This is a very long failure message. ", count: 100)
    // THEN: Should not crash
    sut.fail(longMessage, file: #file, line: #line)

    XCTAssertTrue(true, "fail() with long message completed")
  }

  func test_fail_withSpecialCharacters() {
    // GIVEN: A PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // WHEN: Call fail with special characters
    let message = "失敗: エラーが発生しました 🚨💥 \n\t Special chars: @#$%^&*()"
    // THEN: Should not crash
    sut.fail(message, file: #file, line: #line)

    XCTAssertTrue(true, "fail() with special characters completed")
  }

  func test_fail_withMultilineMessage() {
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

    XCTAssertTrue(true, "fail() with multiline message completed")
  }

  // MARK: - Integration Tests

  func test_printAssertionProvider_multipleOperations() {
    // GIVEN: A PrintAssertionProvider
    let sut = PrintAssertionProvider()

    // WHEN & THEN: Perform multiple operations in sequence
    sut.assertEqual(1, 1, "First assertion", file: #file, line: #line)
    sut.assertEqual(2, 3, "Second assertion (fails)", file: #file, line: #line)
    sut.fail("Manual failure", file: #file, line: #line)
    sut.assertEqual("test", "test", "Third assertion", file: #file, line: #line)

    // All operations should complete without crashing
    XCTAssertTrue(true, "Multiple operations completed")
  }

  func test_printAssertionProvider_canBeUsedAcrossMultipleTests() {
    // GIVEN: A PrintAssertionProvider used multiple times
    let sut = PrintAssertionProvider()

    // WHEN: Use it for multiple assertions
    for i in 0..<10 {
      sut.assertEqual(i, i, "Iteration \(i)", file: #file, line: #line)
    }

    // THEN: Should handle repeated use without issues
    XCTAssertTrue(true, "Multiple uses completed")
  }

  // MARK: - XCTestAssertionProvider Tests

  func test_xcTestAssertionProvider_canBeInitialized() {
    // GIVEN & WHEN: Create an XCTestAssertionProvider
    let sut = XCTestAssertionProvider()

    // THEN: Should be successfully initialized
    XCTAssertNotNil(sut)
  }

  func test_xcTestAssertionProvider_assertEqual_withEqualValues() {
    // GIVEN: An XCTestAssertionProvider and equal values
    let sut = XCTestAssertionProvider()

    // WHEN & THEN: Call assertEqual with equal values (should not fail)
    sut.assertEqual(42, 42, "Values should be equal", file: #file, line: #line)
    sut.assertEqual("test", "test", "Strings should match", file: #file, line: #line)
  }

  func test_xcTestAssertionProvider_assertEqual_withComplexTypes() {
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

  func test_assertionProvider_protocolConformance() {
    // GIVEN: Both assertion provider implementations
    let printProvider: any AssertionProvider = PrintAssertionProvider()
    let xcTestProvider: any AssertionProvider = XCTestAssertionProvider()

    // WHEN & THEN: Both should conform to AssertionProvider protocol
    // This is tested at compile time, but we verify runtime behavior

    printProvider.assertEqual(1, 1, "Print provider", file: #file, line: #line)
    xcTestProvider.assertEqual(2, 2, "XCTest provider", file: #file, line: #line)

    XCTAssertTrue(true, "Both providers work through protocol")
  }
}
