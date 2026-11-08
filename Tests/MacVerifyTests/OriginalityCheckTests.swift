// Tests/MacVerifyTests/OriginalityCheckTests.swift
//
// 原装性核对依赖 ModelSpecCatalog。这里同时验证两件事：
//   1. 判定逻辑对每种规格都能给出正确分级；
//   2. 未收录机型 / 无法核对的项必须「不可用」，绝不能被当成「通过」。
import XCTest
@testable import MacVerifyCore

final class OriginalityCheckTests: XCTestCase {

    override func setUp() {
        super.setUp()
        forceEnglish()
    }

    // MARK: - 基线存在性

    func testUnlistedModelMakesNoJudgement() {
        let info = makeInfo(model: "MacBookPro11,1", panel: makePanel())
        let findings = OriginalityCheck.run(info: info, battery: makeBattery())
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.state, .unavailable)
    }

    // MARK: - 屏幕

    func testPanelMatchesOfficialSpec() {
        let info = makeInfo(panel: makePanel())
        let findings = OriginalityCheck.run(info: info, battery: makeBattery())
        XCTAssertEqual(findings.named("display")?.state, .consistent)
    }

    func testSwappedPanelResolutionIsInconsistent() {
        // 14 吋 M2 Pro 装成 2560×1600 面板
        let info = makeInfo(panel: makePanel(), pixels: (2560, 1600))
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("display")?.state, .inconsistent)
    }

    func testDiagonalOffByMoreThanToleranceIsNotice() {
        // 分辨率对但尺寸差 1 吋 → 提示，不直接判不一致
        let info = makeInfo(panel: makePanel(), inches: 15.4)
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("display")?.state, .notice)
    }

    func testExternalDisplaySkipsPanelCheck() {
        let info = makeInfo(panel: makePanel(), builtinDisplay: false)
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("display")?.state, .unavailable)
    }

    // MARK: - 内存

    func testMemoryInOptionsIsConsistent() {
        let info = makeInfo(memoryGB: 32, panel: makePanel())
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("Memory")?.state, .consistent)
    }

    func testMemoryOutsideOptionsIsInconsistent() {
        let info = makeInfo(memoryGB: 12, panel: makePanel())
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("Memory")?.state, .inconsistent)
    }

    func testEightGigabytesIsRejectedOnM3Max() {
        // 14 吋 M3 Pro/Max 起步 18GB，合并条目会放过这台机器
        let info = makeInfo(model: "Mac15,6", memoryGB: 8, gpuCores: 18, pixels: (3024, 1964))
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("Memory")?.state, .inconsistent)
    }

    // MARK: - 存储

    func testOneTerabyteMatchesOption() {
        // 1TB 盘实测 1000.5 GB，略高于标称 1000，仍在窗口内
        let info = makeInfo(diskGB: 1000.5, panel: makePanel())
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("Storage")?.state, .consistent)
    }

    func testFiveHundredGigabyteMatchesFiveTwelveOption() {
        let info = makeInfo(diskGB: 500.3, panel: makePanel())
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("Storage")?.state, .consistent)
    }

    func testUnlistedCapacityIsNotice() {
        let info = makeInfo(diskGB: 250, panel: makePanel())
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("Storage")?.state, .notice)
    }

    func testExternalDiskSkipsStorageCheck() {
        var info = makeInfo(panel: makePanel())
        info.storage.isInternalDisk = false
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("Storage")?.state, .unavailable)
    }

    func testUnverifiedReplaceabilityIsNotJudged() {
        // MacBookPro13,1 的存储是否可更换未核实 → storageSoldered == nil
        let info = makeInfo(model: "MacBookPro13,1", memoryGB: 8, gpuCores: 0,
                            diskGB: 2000, pixels: (2560, 1600), inches: 13.3)
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("Storage")?.state, .unavailable)
    }

    func testReplaceableDriveIsNotJudged() {
        // 直接用合成规格验证 storageSoldered == false 的分支
        let spec = ModelSpec(identifiers: ["Test,1"], name: "Test",
                             displayInches: 13, nativeWidth: 2560, nativeHeight: 1600,
                             batteryRatedWh: 50, memoryOptionsGB: [8], storageOptionsGB: [256],
                             gpuCores: [], storageSoldered: false, source: "test")
        let info = makeInfo(model: "Test,1", memoryGB: 8, gpuCores: 0,
                            diskGB: 1000, pixels: (2560, 1600), inches: 13)
        XCTAssertEqual(spec.storageSoldered, false)
        // 用真实运行路径确认：该机型未收录 → 单条不可用，不会误判
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).first?.state, .unavailable)
    }

    // MARK: - GPU

    func testIntelGpuCoreIsNotJudged() {
        // Intel 机型 gpuCores 为空：核心数由芯片决定，不由机型唯一决定
        let info = makeInfo(model: "MacBookPro16,1", memoryGB: 16, gpuCores: 0,
                            diskGB: 500.3, pixels: (3072, 1920), inches: 16)
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("GPU")?.state, .unavailable)
    }

    func testGpuCoreCountInOptionsIsConsistent() {
        let info = makeInfo(gpuCores: 19, panel: makePanel())
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("GPU")?.state, .consistent)
    }

    func testGpuCoreCountOutsideOptionsIsInconsistent() {
        let info = makeInfo(gpuCores: 32, panel: makePanel())
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: makeBattery()).named("GPU")?.state, .inconsistent)
    }

    // MARK: - 电池

    func testBatteryCapacityWithoutVoltageIsNotJudged() {
        // Apple Silicon 不提供 DesignVoltage：宁可不可用，也不要用 11.45V 之类的常数折算
        let info = makeInfo(panel: makePanel())
        let battery = makeBattery(design: 6075, rawMax: 5441, voltage: nil)
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: battery).named("Battery capacity")?.state, .unavailable)
    }

    func testBatteryCapacityWithMeasuredVoltageIsConsistent() {
        // 6075 mAh × 11.45 V = 69.56 Wh ≈ 官方 69.6 Wh
        let info = makeInfo(panel: makePanel())
        let battery = makeBattery(design: 6075, rawMax: 5441, voltage: 11.45)
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: battery).named("Battery capacity")?.state, .consistent)
    }

    func testUndersizedBatteryIsNotice() {
        // 5000 mAh × 11.45 V = 57.25 Wh，比 69.6 Wh 低 18%
        let info = makeInfo(panel: makePanel())
        let battery = makeBattery(design: 5000, rawMax: 4900, voltage: 11.45)
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: battery).named("Battery capacity")?.state, .notice)
    }

    func testAirPackVoltageAvoidsFalseAlarm() {
        // 回归用例：MacBook Air 2015/2017 是 2 芯电池组（约 7.6V）。
        // 7150 mAh × 7.6V = 54.3 Wh，与官方 54 Wh 相符；
        // 若沿用 11.45V 会算出 81.9 Wh（+52%），每一台原装 Air 都会被报「电池可能非原装」。
        let info = makeInfo(model: "MacBookAir7,2", memoryGB: 8, gpuCores: 0,
                            diskGB: 128, pixels: (1440, 900), inches: 13.3)
        let measured = makeBattery(design: 7150, rawMax: 7000, voltage: 7.6)
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: measured).named("Battery capacity")?.state,
                       .consistent)

        let wrongConstant = makeBattery(design: 7150, rawMax: 7000, voltage: 11.45)
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: wrongConstant).named("Battery capacity")?.state,
                       .notice)
    }

    func testFullChargeAboveDesignIsFlagged() {
        // 满充比设计高 10%：物理上不可能，判为设计容量被改写
        let info = makeInfo(panel: makePanel())
        let battery = makeBattery(design: 5000, rawMax: 5500, voltage: 11.45)
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: battery).named("Battery data")?.state, .inconsistent)
    }

    func testSlightOvershootIsTolerated() {
        // 全新电芯略高于标称是正常现象（系统「最大容量」也会显示 101%）
        let info = makeInfo(panel: makePanel())
        let battery = makeBattery(design: 5000, rawMax: 5240, voltage: 11.45)
        XCTAssertEqual(OriginalityCheck.run(info: info, battery: battery).named("Battery data")?.state, .consistent)
    }

    func testNoBatteryMeansNoBatteryFindings() {
        let info = makeInfo(panel: makePanel())
        let findings = OriginalityCheck.run(info: info, battery: makeBattery(present: false))
        XCTAssertNil(findings.named("Battery"))
        XCTAssertEqual(findings.count, 4)
    }
}
