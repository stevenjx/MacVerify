// Tests/MacVerifyTests/EDIDTests.swift
import XCTest
@testable import MacVerifyCore

/// EDID 解析属于「一错就是错一整块面板信息」的代码，用构造出来的字节逐字段验。
final class EDIDTests: XCTestCase {

    override func setUp() {
        super.setUp()
        forceEnglish()
    }

    /// 造一份 128 字节 EDID。checksum 自动补到第 127 字节。
    private func makeEDID(
        manufacturer: (Character, Character, Character) = ("A", "P", "P"),
        product: Int = 0xA04E,
        serial: UInt32 = 0xFD62_6D62,
        week: Int = 12,
        yearOffset: Int = 8,
        validHeader: Bool = true,
        validChecksum: Bool = true
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 128)
        if validHeader {
            bytes[0] = 0x00
            bytes[1] = 0xFF
            bytes[2] = 0xFF
            bytes[3] = 0xFF
            bytes[4] = 0xFF
            bytes[5] = 0xFF
            bytes[6] = 0xFF
            bytes[7] = 0x00
        }

        func fiveBit(_ c: Character) -> Int {
            Int(c.asciiValue ?? 0) - 64
        }
        let id = (fiveBit(manufacturer.0) << 10) | (fiveBit(manufacturer.1) << 5) | fiveBit(manufacturer.2)
        bytes[8] = UInt8((id >> 8) & 0xFF)
        bytes[9] = UInt8(id & 0xFF)

        bytes[10] = UInt8(product & 0xFF)
        bytes[11] = UInt8((product >> 8) & 0xFF)
        for i in 0..<4 {
            bytes[12 + i] = UInt8((serial >> (8 * UInt32(i))) & 0xFF)
        }
        bytes[16] = UInt8(week & 0xFF)
        bytes[17] = UInt8(yearOffset & 0xFF)

        if validChecksum {
            let sum = bytes[0..<127].reduce(0) { ($0 + Int($1)) & 0xFF }
            bytes[127] = UInt8((256 - sum) & 0xFF)
        } else {
            bytes[127] = 0x00
        }
        return Data(bytes)
    }

    func testParsesAllFields() {
        let edid = EDIDReader.parse(makeEDID())
        XCTAssertNotNil(edid)
        XCTAssertEqual(edid?.manufacturerName, "APP")
        XCTAssertEqual(edid?.manufacturerID, 0x0610)
        XCTAssertEqual(edid?.productCode, 0xA04E)
        XCTAssertEqual(edid?.serialNumber, 0xFD62_6D62)
        XCTAssertEqual(edid?.week, 12)
        XCTAssertEqual(edid?.year, 1998)
    }

    func testManufacturerDecodingHandlesLowBits() {
        // "SAM" 之类含 A 的厂商码，验证三个 5 bit 字段拼接顺序没错位
        let edid = EDIDReader.parse(makeEDID(manufacturer: ("S", "A", "M")))
        XCTAssertEqual(edid?.manufacturerName, "SAM")
    }

    func testYearZeroIsNotNineteenNinety() {
        // 未写入生产日期时 year 字节为 0，绝不能算成 1990 年
        let edid = EDIDReader.parse(makeEDID(yearOffset: 0))
        XCTAssertEqual(edid?.year, 0)

        var display = DisplayInfo()
        display.edid = edid
        XCTAssertEqual(display.edidProductionText, "—")
    }

    func testRejectsBadHeader() {
        XCTAssertNil(EDIDReader.parse(makeEDID(validHeader: false)))
    }

    func testRejectsBadChecksum() {
        // 校验和不对说明数据被截断或损坏，宁可显示「不可用」也不能把垃圾当面板信息
        XCTAssertNil(EDIDReader.parse(makeEDID(validChecksum: false)))
    }

    func testRejectsShortData() {
        let short = makeEDID().prefix(127)
        XCTAssertNil(EDIDReader.parse(Data(short)))
    }

    func testPanelProductionTextRequiresRealDate() {
        var panel = PanelIdentity()
        panel.year = 2023
        panel.week = 8
        XCTAssertEqual(panel.productionText, "2023 / W08")

        panel.week = 0
        XCTAssertEqual(panel.productionText, "—", "周为 0 说明未写入日期，不应显示")
    }
}
