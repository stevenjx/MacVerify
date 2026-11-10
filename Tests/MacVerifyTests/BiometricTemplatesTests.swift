// Tests/MacVerifyTests/BiometricTemplatesTests.swift
import XCTest
@testable import MacVerifyCore

/// bioutil 输出解析：数量读错会让「录入成功」变成假的，所以单独测。
final class BiometricTemplatesTests: XCTestCase {

    func testReadsCountFromRealOutput() {
        let output = """
        User 501:\t1 biometric template(s)
        Operation performed successfully.
        """
        XCTAssertEqual(BiometricTemplates.parse(output), 1)
    }

    func testReadsMultiDigitCount() {
        let output = "User 501:\t10 biometric template(s)\nOperation performed successfully.\n"
        XCTAssertEqual(BiometricTemplates.parse(output), 10)
    }

    /// 第一段数字是 uid，不能被当成数量
    func testIgnoresUserID() {
        let output = "User 12345:\t3 biometric template(s)"
        XCTAssertEqual(BiometricTemplates.parse(output), 3)
    }

    func testZeroIsAValidAnswer() {
        let output = "User 501:\t0 biometric template(s)"
        XCTAssertEqual(BiometricTemplates.parse(output), 0)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(BiometricTemplates.parse(""))
        XCTAssertNil(BiometricTemplates.parse("Operation performed successfully."))
        XCTAssertNil(BiometricTemplates.parse("User 501: biometric template(s)"))
    }
}
