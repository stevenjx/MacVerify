// Tests/MacVerifyTests/Support.swift
//
// 测试公共件：合成数据构造器 + 固定语言。
//
// 这些用例全部基于「构造出来的输入」，不读本机硬件：
// CI 上没有电池、没有内建屏的机器跑出来也要是同一套结果。
// 唯一读真实接口的是 ReportService 的端到端用例，它只断言结构，不断言具体数值。
import Foundation
import XCTest
@testable import MacVerifyCore

/// 强制英文断言，避免 CI 的 Locale 影响断言文本。
func forceEnglish() {
    UserDefaults.standard.set("english", forKey: "macverify.language")
    Localization.shared.language = .english
}

/// 构造一台机器的信息。默认值刻意都填「有值」，让每个用例只改自己关心的字段。
func makeInfo(
    model: String = "Mac14,9",
    chip: String = "Apple M2 Pro",
    chipFromSysctl: String? = "Apple M2 Pro",
    memoryGB: Int = 16,
    gpuCores: Int = 16,
    diskGB: Double = 1000.5,
    panel: PanelIdentity? = nil,
    builtinDisplay: Bool = true,
    pixels: (Int, Int) = (3024, 1964),
    inches: Double = 14.2
) -> MacSystemInfo {
    var info = MacSystemInfo()
    info.modelIdentifier = model
    info.modelFromSysctl = model
    info.serialNumber = "KVNY9P2061"
    info.serialFromIOKit = "KVNY9P2061"
    info.chipName = chip
    info.chipFromSysctl = chipFromSysctl
    info.memoryGB = memoryGB
    info.memoryBytesFromSysctl = memoryGB * 1_073_741_824
    info.gpuCores = gpuCores
    info.storage.physicalBytes = UInt64(diskGB * 1_000_000_000)
    info.storage.diskSizeFromDiskutil = UInt64(diskGB * 1_000_000_000)
    info.storage.diskSizeFromIOMedia = UInt64(diskGB * 1_000_000_000)
    info.storage.deviceName = "APPLE SSD AP1024Z"
    info.storage.isInternalDisk = true
    info.display.isBuiltin = builtinDisplay
    info.display.pixelWidth = pixels.0
    info.display.pixelHeight = pixels.1
    info.display.inches = inches
    info.display.modelID = panel?.productID ?? 0
    info.display.panel = panel
    return info
}

func makePanel(productID: Int = 41038, vendorID: Int = 1552, serial: UInt64 = 0xFD62_6D62) -> PanelIdentity {
    var panel = PanelIdentity()
    panel.vendorID = vendorID
    panel.productID = productID
    panel.serialNumber = serial
    return panel
}

func makeBattery(
    design: Int = 6075,
    rawMax: Int = 5441,
    nominal: Int = 0,
    voltage: Double? = nil,
    present: Bool = true,
    cycles: Int = 157,
    designCycles: Int = 1000
) -> BatterySnapshot {
    var battery = BatterySnapshot()
    battery.isPresent = present
    battery.designCapacity = design
    battery.rawMaxCapacity = rawMax
    battery.nominalCapacity = nominal
    battery.designVoltage = voltage
    battery.cycleCount = cycles
    battery.cycleCountAvailable = true
    battery.designCycleCount = designCycles
    battery.designCycleCountAvailable = true
    return battery
}

extension Array where Element == AuditFinding {
    func named(_ keyword: String) -> AuditFinding? {
        first { $0.title.contains(keyword) }
    }
}

extension Array where Element == OriginalityFinding {
    func named(_ keyword: String) -> OriginalityFinding? {
        first { $0.title.contains(keyword) }
    }
}

/// 每个用例独立的 UserDefaults 域，避免并行执行时互相清库。
func makeIsolatedDefaults(function: String = #function) -> UserDefaults {
    let name = "MacVerifyTests.\(function).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
