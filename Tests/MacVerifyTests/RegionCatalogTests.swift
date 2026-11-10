// Tests/MacVerifyTests/RegionCatalogTests.swift
import XCTest
@testable import MacVerifyCore

/// 区域只能从配置编号后缀读，读不出来必须返回 nil —— 猜错地区比显示未知更有害。
final class RegionCatalogTests: XCTestCase {

    override func setUp() {
        super.setUp()
        forceEnglish()
    }

    func testTwoLetterCodes() {
        XCTAssertEqual(RegionCatalog.region(forPartNumber: "Z17G000NALL/A")?.code, "LL")
        XCTAssertEqual(RegionCatalog.region(forPartNumber: "MRX33ZP/A")?.code, "ZP")
        XCTAssertEqual(RegionCatalog.region(forPartNumber: "MNYF2CH/A")?.code, "CH")
        XCTAssertEqual(RegionCatalog.region(forPartNumber: "MXD42ZA/A")?.code, "ZA")
        XCTAssertEqual(RegionCatalog.region(forPartNumber: "MKGT3TH/A")?.code, "TH")
        XCTAssertEqual(RegionCatalog.region(forPartNumber: "MKU22ZD/A")?.code, "ZD")
    }

    func testSingleLetterCodes() {
        // MF839D/A 是德版 13" Retina MacBook Pro，后缀只有一位
        XCTAssertEqual(RegionCatalog.region(forPartNumber: "MF839D/A")?.code, "D")
        XCTAssertEqual(RegionCatalog.region(forPartNumber: "MXVV2X/A")?.code, "X")
        XCTAssertEqual(RegionCatalog.region(forPartNumber: "MJLT2B/A")?.code, "B")
    }

    /// 「…NALL」结尾必须按两字母 LL 判定，不能退化成单字母 L
    func testPrefersTwoLetterMatch() {
        let region = RegionCatalog.region(forPartNumber: "Z17G000NALL/A")
        XCTAssertEqual(region?.code, "LL")
        XCTAssertEqual(region?.name, "United States")
    }

    func testLowercaseInputIsAccepted() {
        XCTAssertEqual(RegionCatalog.region(forPartNumber: " z17g000nall/a ")?.code, "LL")
    }

    func testUnknownCodeReturnsNil() {
        // DN 不在已确认的对照表里：宁可显示未知，也不写成「德国」
        XCTAssertNil(RegionCatalog.region(forPartNumber: "MXVV2DN/A"))
    }

    func testMalformedInputReturnsNil() {
        XCTAssertNil(RegionCatalog.region(forPartNumber: ""))
        XCTAssertNil(RegionCatalog.region(forPartNumber: "—"))
        XCTAssertNil(RegionCatalog.region(forPartNumber: "A2779"))
        // Apple 文档里的占位符（xx 为通配）不能当成澳版
        XCTAssertNil(RegionCatalog.region(forPartNumber: "MQRJ3xx/A"))
        XCTAssertNil(RegionCatalog.region(forPartNumber: "MQRJ3XX/A"))
    }
}
