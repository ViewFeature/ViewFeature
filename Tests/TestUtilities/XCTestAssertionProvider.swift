import Foundation
import ViewFeature
import XCTest

/// XCTest-based assertion provider for use in test targets
public struct XCTestAssertionProvider: AssertionProvider {
    public init() {}

    public func assertEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual, expected, message, file: file, line: line)
    }

    public func fail(
        _ message: String,
        file: StaticString,
        line: UInt
    ) {
        XCTFail(message, file: file, line: line)
    }
}
