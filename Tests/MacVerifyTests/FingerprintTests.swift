// Tests/MacVerifyTests/FingerprintTests.swift
import XCTest
@testable import MacVerifyCore

/// 指纹的语义边界：
/// 锁定身份（换序列号 / 换屏 / 换盘会变），不锁使用痕迹（电池循环增加不会变）。
final class FingerprintTests: XCTestCase {

    private let base: [String: String] = [
        "model_identifier": "Mac14,9",
        "serial_number": "KVNY9P2061",
        "chip": "Apple M2 Pro",
        "memory": "16 GB",
        "storage_physical_bytes": "1000555581440",
        "storage_capacity": "1TB",
        "panel_product": "0xA04E",
        "panel_serial": "FD626D62",
        "battery_serial": "F8Y1234567"
    ]

    func testStableForSameInput() {
        XCTAssertEqual(DeviceFingerprint.compute(base), DeviceFingerprint.compute(base))
    }

    func testSixteenUppercaseHexCharacters() {
        let value = DeviceFingerprint.compute(base)
        XCTAssertEqual(value.count, 16)
        XCTAssertEqual(value, value.uppercased())
        XCTAssertTrue(value.allSatisfy { $0.isHexDigit })
    }

    func testSerialSwapChangesFingerprint() {
        var other = base
        other["serial_number"] = "C02XXXXXXXX"
        XCTAssertNotEqual(DeviceFingerprint.compute(base), DeviceFingerprint.compute(other))
    }

    func testPanelSwapChangesFingerprint() {
        var other = base
        other["panel_serial"] = "DEADBEEF"
        XCTAssertNotEqual(DeviceFingerprint.compute(base), DeviceFingerprint.compute(other))
    }

    func testDriveSwapChangesFingerprint() {
        var other = base
        other["storage_physical_bytes"] = "500277790720"
        XCTAssertNotEqual(DeviceFingerprint.compute(base), DeviceFingerprint.compute(other))
    }

    func testUsageCountersDoNotChangeFingerprint() {
        // 电池循环、上电时长属于会漂移的使用痕迹，不应影响身份指纹
        var other = base
        other["battery_cycle_count"] = "999"
        other["smart_power_on_hours"] = "99999"
        XCTAssertEqual(DeviceFingerprint.compute(base), DeviceFingerprint.compute(other))
    }

    func testMissingFieldIsTreatedAsUnavailableNotSkipped() {
        // 缺字段按 unavailable 参与计算：字段集合变化必须改变结果，
        // 否则「读不到」和「读到了」会算出同一个指纹
        var other = base
        other.removeValue(forKey: "battery_serial")
        XCTAssertNotEqual(DeviceFingerprint.compute(base), DeviceFingerprint.compute(other))
        XCTAssertEqual(DeviceFingerprint.compute(other),
                       DeviceFingerprint.compute({ var d = other; d["battery_serial"] = "unavailable"; return d }()))
    }

    func testDisplayFormat() {
        XCTAssertEqual(DeviceFingerprint.display("A6BC32BF3D35DF5A"), "A6BC32BF-3D35DF5A")
        XCTAssertEqual(DeviceFingerprint.display(""), "—")
        XCTAssertEqual(DeviceFingerprint.display("ABC"), "ABC")
    }
}
