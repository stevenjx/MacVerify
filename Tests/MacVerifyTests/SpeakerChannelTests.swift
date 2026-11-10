// Tests/MacVerifyTests/SpeakerChannelTests.swift
import XCTest
@testable import MacVerifyCore

/// 声道到声像的映射：写错一侧就会「左边选成右边」，而且只有听的人能发现。
final class SpeakerChannelTests: XCTestCase {

    func testPanValues() {
        XCTAssertEqual(PlayChannel.left.pan, -1)
        XCTAssertEqual(PlayChannel.both.pan, 0)
        XCTAssertEqual(PlayChannel.right.pan, 1)
    }

    /// pan 是左右平衡：-1 时右声道完全不响，+1 时左声道完全不响
    func testPanIsFullBalanceNotPartial() {
        XCTAssertEqual(abs(PlayChannel.left.pan), 1)
        XCTAssertEqual(abs(PlayChannel.right.pan), 1)
    }

    func testAllCasesCovered() {
        XCTAssertEqual(PlayChannel.allCases.count, 3)
        XCTAssertEqual(Set(PlayChannel.allCases.map(\.pan)), [-1, 0, 1])
    }
}
