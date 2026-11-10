// Tests/MacVerifyTests/BatteryHealthTests.swift
import XCTest
@testable import MacVerifyCore

/// 电池健康度必须与 macOS「系统设置 → 电池」口径一致：
/// AppleRawMaxCapacity ÷ DesignCapacity，且分级全 App 只用一套阈值。
final class BatteryHealthTests: XCTestCase {

    override func setUp() {
        super.setUp()
        forceEnglish()
    }

    func testMatchesSystemSettingsOnKnownMachine() {
        // 实测样本：设计 6075 mAh、AppleRawMax 5441 mAh → 89.6%，macOS 显示 90%
        let battery = makeBattery(design: 6075, rawMax: 5441)
        let health = try? XCTUnwrap(battery.healthPercent)
        XCTAssertEqual(health ?? 0, 89.56, accuracy: 0.01)
        XCTAssertEqual(battery.healthGrade, .good)
    }

    func testPrefersRawMaxOverNominal() {
        // NominalChargeCapacity 会算出 92%，比系统高 2 个百分点；必须优先用 AppleRawMaxCapacity
        let battery = makeBattery(design: 6075, rawMax: 5441, nominal: 5591)
        XCTAssertEqual(battery.healthPercent ?? 0, 89.56, accuracy: 0.01)
        XCTAssertEqual(battery.healthCapacity, 5441)
    }

    func testFallsBackToNominalWhenRawMaxMissing() {
        let battery = makeBattery(design: 6075, rawMax: 0, nominal: 5591)
        XCTAssertEqual(battery.healthPercent ?? 0, 92.03, accuracy: 0.01)
    }

    func testCapsAtHundredPercent() {
        // 全新电芯的满充容量可能略高于标称，健康度不能超过 100%
        let battery = makeBattery(design: 5000, rawMax: 5200)
        XCTAssertEqual(battery.healthPercent ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(battery.healthGrade, .excellent)
    }

    func testUnavailableWhenDesignCapacityMissing() {
        let battery = makeBattery(design: 0, rawMax: 5441)
        XCTAssertNil(battery.healthPercent)
        XCTAssertEqual(battery.healthGrade, .unknown)
    }

    func testGradeBoundaries() {
        // 阈值：>=90 优秀、80..<90 良好、70..<80 一般、<70 建议检修
        let cases: [(Int, Int, HealthGrade)] = [
            (5000, 4550, .excellent),   // 91.0%
            (5000, 4500, .excellent),   // 90.0% 边界
            (5000, 4499, .good),        // 89.98%
            (5000, 4000, .good),        // 80.0% 边界
            (5000, 3999, .fair),        // 79.98%
            (5000, 3500, .fair),        // 70.0% 边界
            (5000, 3499, .service)      // 69.98%
        ]
        for (design, raw, expected) in cases {
            let battery = makeBattery(design: design, rawMax: raw)
            XCTAssertEqual(battery.healthGrade, expected,
                           "\(raw)/\(design) 应为 \(expected)")
        }
    }

}
