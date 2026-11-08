// Tests/MacVerifyTests/ConsistencyAuditTests.swift
//
// 一致性核验的每一条都必须能「一致」也能「不一致」，
// 否则等于没检查：只测通过路径，篡改也会显示全程绿灯。
import XCTest
@testable import MacVerifyCore

final class ConsistencyAuditTests: XCTestCase {

    override func setUp() {
        super.setUp()
        forceEnglish()
    }

    func testCleanMachineIsAllConsistent() {
        let info = makeInfo(panel: makePanel())
        let findings = ConsistencyAudit.run(info: info)
        XCTAssertEqual(findings.count, 7)
        for finding in findings {
            XCTAssertEqual(finding.state, .consistent, "\(finding.title): \(finding.detail)")
        }
    }

    func testModelIdentifierMismatchIsInconsistent() {
        var info = makeInfo(panel: makePanel())
        info.modelIdentifier = "Mac15,3"   // 系统报告被改成 M3 14"
        let finding = ConsistencyAudit.run(info: info).named("Model identifier")
        XCTAssertEqual(finding?.state, .inconsistent)
    }

    func testModelIdentifierUnavailableWhenKernelSilent() {
        var info = makeInfo(panel: makePanel())
        info.modelFromSysctl = nil
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Model identifier")?.state, .unavailable)
    }

    func testSerialMismatchIsInconsistent() {
        var info = makeInfo(panel: makePanel())
        info.serialFromIOKit = "C02ZZZZZZZZ"
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Serial")?.state, .inconsistent)
    }

    func testIntelChipShortNameMatchesFullBrandString() {
        // 回归用例：曾经用相等比较，导致每台 Intel 机器都被判成篡改
        let info = makeInfo(
            model: "MacBookPro16,1",
            chip: "Intel Core i7",
            chipFromSysctl: "Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz",
            gpuCores: 0
        )
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Chip")?.state, .consistent)
    }

    func testAppleSiliconChipEqualNamesMatch() {
        let info = makeInfo(chip: "Apple M2 Pro", chipFromSysctl: "Apple M2 Pro")
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Chip")?.state, .consistent)
    }

    func testGenuinelyDifferentChipsAreInconsistent() {
        let info = makeInfo(chip: "Apple M2 Pro", chipFromSysctl: "Apple M1 Max")
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Chip")?.state, .inconsistent)
    }

    func testDiskSizeDisagreementIsInconsistent() {
        var info = makeInfo(panel: makePanel())
        info.storage.diskSizeFromIOMedia = UInt64(500.3 * 1_000_000_000)
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Disk size")?.state, .inconsistent)
    }

    func testDiskSizeRoundOffIsAccepted() {
        // 同一块盘两种接口取整到不同字节级，0.1% 内视为一致
        var info = makeInfo(panel: makePanel())
        info.storage.diskSizeFromDiskutil = 1_000_555_581_440
        info.storage.diskSizeFromIOMedia = 1_000_555_581_439
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Disk size")?.state, .consistent)
    }

    func testExternalBootDiskIsNotJudged() {
        var info = makeInfo(panel: makePanel())
        info.storage.isInternalDisk = false
        info.storage.deviceName = "Samsung SSD 970 EVO"
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Original drive")?.state, .unavailable)
    }

    func testThirdPartySSDIsNoticeNotTampering() {
        // Intel 机型可正常换盘，只能说「不是原厂命名」，不能下篡改结论
        var info = makeInfo(panel: makePanel())
        info.storage.deviceName = "Samsung SSD 970 EVO"
        let finding = ConsistencyAudit.run(info: info).named("Original drive")
        XCTAssertEqual(finding?.state, .notice)
    }

    func testPanelProductMismatchIsInconsistent() {
        var info = makeInfo(panel: makePanel(productID: 41038))
        info.display.modelID = 0x1234
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Built-in display")?.state, .inconsistent)
    }

    func testPanelUnavailableOnAppleSiliconIsNotAFailure() {
        var info = makeInfo(panel: nil)
        info.display.modelID = 0
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Built-in display")?.state, .unavailable)
    }

    func testFourGigabytesIsStandard() {
        // 回归用例：MacBook Air 2015/2017 起售就是 4GB，曾被判成「非常见配置」
        let info = makeInfo(memoryGB: 4)
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Memory size")?.state, .consistent)
    }

    func testOddMemorySizeIsNotice() {
        let info = makeInfo(memoryGB: 12)
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Memory size")?.state, .notice)
    }

    func testMemoryUnavailableWithoutKernelValue() {
        var info = makeInfo()
        info.memoryBytesFromSysctl = 0
        XCTAssertEqual(ConsistencyAudit.run(info: info).named("Memory size")?.state, .unavailable)
    }
}
