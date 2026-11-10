// Tests/MacVerifyTests/UpdateCheckerTests.swift
import XCTest
@testable import MacVerifyCore

/// 版本比较与 release 解析。这两件事决定「要不要提示更新」，
/// 错一次就会一直提示或者永远不提示，所以单独测。
final class UpdateCheckerTests: XCTestCase {

    // MARK: - 版本比较

    func testNewerVersions() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.11", than: "1.0.10"))
        XCTAssertTrue(UpdateChecker.isNewer("1.1", than: "1.0.99"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9.9"))
        // 带 v 前缀的 tag 与不带前缀的版本要能比
        XCTAssertTrue(UpdateChecker.isNewer("v1.0.12", than: "1.0.10"))
    }

    func testSameOrOlder() {
        XCTAssertFalse(UpdateChecker.isNewer("1.0.10", than: "1.0.10"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.9", than: "1.0.10"))
        // 1.0 与 1.0.0 是同一个版本，缺的段按 0 算
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("v1.0.9", than: "1.0.10"))
    }

    /// 1.0.10 与 1.0.9 只能按数字段比较；按字符串比会把 1.0.10 判成更旧
    func testComparesNumericallyNotLexically() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.9", than: "1.0.10"))
    }

    func testUnparsableVersionsNeverCountAsNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("latest", than: "1.0.10"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.x", than: "1.0.10"))
        XCTAssertFalse(UpdateChecker.isNewer("", than: "1.0.10"))
    }

    func testNumbersParsing() {
        XCTAssertEqual(UpdateChecker.numbers(in: "v1.0.12"), [1, 0, 12])
        XCTAssertEqual(UpdateChecker.numbers(in: "1.1.0-beta.2"), [1, 1, 0])
        XCTAssertNil(UpdateChecker.numbers(in: "nightly"))
    }

    // MARK: - Release 解析

    private func payload(tag: String = "v1.0.12",
                         assets: [(String, String)]) -> Data {
        let list = assets.map { ["name": $0.0, "browser_download_url": $0.1] }
        let root: [String: Any] = ["tag_name": tag, "assets": list]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    func testPicksTheDMGNamedAfterTheVersion() {
        let data = payload(assets: [
            ("MacVerify-1.0.12.dmg", "https://example.com/MacVerify-1.0.12.dmg"),
            ("MacVerify-1.0.12.zip", "https://example.com/MacVerify-1.0.12.zip")
        ])
        let release = UpdateChecker.parseLatestRelease(data)
        XCTAssertEqual(release?.version, "1.0.12")
        XCTAssertEqual(release?.tag, "v1.0.12")
        XCTAssertEqual(release?.assetName, "MacVerify-1.0.12.dmg")
        XCTAssertEqual(release?.downloadURL.absoluteString, "https://example.com/MacVerify-1.0.12.dmg")
    }

    /// 只有一个 DMG、名字又没带版本号时，仍然要能下载
    func testFallsBackToTheOnlyDMG() {
        let data = payload(assets: [
            ("MacVerify.dmg", "https://example.com/MacVerify.dmg"),
            ("notes.txt", "https://example.com/notes.txt")
        ])
        XCTAssertEqual(UpdateChecker.parseLatestRelease(data)?.assetName, "MacVerify.dmg")
    }

    func testRejectsReleaseWithoutDMG() {
        let data = payload(assets: [("macverify.zip", "https://example.com/m.zip")])
        XCTAssertNil(UpdateChecker.parseLatestRelease(data))
    }

    func testRejectsGarbage() {
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data("{\"assets\":[]}".utf8)))
    }
}
