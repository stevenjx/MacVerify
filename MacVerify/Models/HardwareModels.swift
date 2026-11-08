// Models/HardwareModels.swift
import Foundation

/// 内建/外接面板的身份信息。来源：CGDisplay + system_profiler SPDisplaysDataType。
/// 注意：EDID 原始块在 Apple Silicon 上不向用户态开放，这不代表拿不到面板身份。
struct PanelIdentity {
    var vendorID: Int = 0
    var productID: Int = 0
    var serialNumber: UInt64 = 0
    var typeName: String = ""
    var connectionType: String = ""
    var week: Int = -1
    var year: Int = -1

    var vendorText: String { vendorID > 0 ? String(format: "0x%04X", vendorID) : "—" }
    var productText: String { productID > 0 ? String(format: "0x%04X", productID) : "—" }
    var serialText: String { serialNumber > 0 ? String(serialNumber, radix: 16, uppercase: true) : "—" }

    /// week / year 均为 0 表示面板未写入生产日期，不能当成 1990 年第 0 周
    var productionText: String {
        guard year > 1990, week > 0, week <= 53 else { return "—" }
        return String(format: "%d / W%02d", year, week)
    }
}

struct DisplayInfo {
    var name: String = "—"
    var isBuiltin: Bool = false
    var inches: Double = 0
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var scale: Double = 1
    var refreshRate: Double = 0
    var vendorID: Int = 0
    var modelID: Int = 0
    var serialNumber: UInt32 = 0
    var colorSpaceName: String = "—"
    var edid: EDIDInfo? = nil
    var panel: PanelIdentity? = nil

    var resolutionText: String {
        guard pixelWidth > 0, pixelHeight > 0 else { return "—" }
        return "\(pixelWidth) × \(pixelHeight)"
    }

    var inchText: String {
        inches > 0 ? String(format: "%.1f″", inches) : "—"
    }

    var edidSerialText: String {
        guard let edid = edid else { return "—" }
        if edid.serialNumber > 0 { return String(format: "%08X", edid.serialNumber) }
        return "—"
    }

    var edidManufacturerText: String {
        guard let edid = edid else { return "—" }
        return edid.manufacturerName.isEmpty ? "—" : edid.manufacturerName
    }

    var edidProductionText: String {
        guard let edid = edid, edid.year > 0 else { return "—" }
        return "\(edid.year) / W\(String(format: "%02d", edid.week))"
    }
}

struct EDIDInfo {
    var manufacturerID: Int = 0
    var manufacturerName: String = ""
    var productCode: Int = 0
    var serialNumber: UInt32 = 0
    var year: Int = 0
    var week: Int = 0
}

struct StorageInfo {
    /// 物理介质容量（diskutil / IOMedia Size），与"卷可用容量"不是一回事
    var physicalBytes: UInt64 = 0
    /// diskutil 报告值，与 IOMedia 值交叉比对
    var diskSizeFromDiskutil: UInt64 = 0
    var diskSizeFromIOMedia: UInt64 = 0
    /// 启动盘是否为机身内建介质。从外接盘启动时，容量/型号都不代表内置 SSD。
    var isInternalDisk: Bool? = nil
    var deviceName: String = "—"
    var medium: String = "—"
    /// 卷/容器级累计读写（APFS Statistics，从容器创建起算，格式化会清零）
    var readBytes: UInt64 = 0
    var writtenBytes: UInt64 = 0
    var statisticsAvailable = false

    // MARK: - SMART（NVMe 原生，全生命周期）

    var smartAvailable = false
    /// diskutil 的 SMARTStatus，通常是 "Verified"
    var smartStatusText: String? = nil
    /// 寿命已消耗百分比（NVMe Percentage Used）
    var smartPercentageUsed: Int? = nil
    var smartHealthPercent: Int? = nil
    /// 剩余备用块百分比及其告警阈值
    var smartAvailableSpare: Int? = nil
    var smartSpareThreshold: Int? = nil
    var smartMediaErrors: Int? = nil
    var smartErrorLogEntries: Int? = nil
    var smartCriticalWarning: Int? = nil
    /// 摄氏温度
    var smartTemperature: Double? = nil
    var smartPowerCycles: Int? = nil
    var smartPowerOnHours: Int? = nil
    var smartUnsafeShutdowns: Int? = nil
    /// 生命周期累计读写（Data Units × 512,000 字节）
    var smartLifetimeReadBytes: UInt64? = nil
    var smartLifetimeWrittenBytes: UInt64? = nil
    var smartHostReadCommands: UInt64? = nil
    var smartHostWriteCommands: UInt64? = nil
    /// 数据来源：diskutil 或 IOKit
    var smartSource: String? = nil

    /// 标称容量（如 1TB / 512GB）。按物理介质字节数取最接近的零售规格。
    var marketingCapacity: String {
        guard physicalBytes > 0 else { return "—" }
        let decimalGB = Double(physicalBytes) / 1_000_000_000
        let candidates: [(Double, String)] = [(128, "128GB"), (256, "256GB"), (512, "512GB"),
                                             (1024, "1TB"), (2048, "2TB"), (4096, "4TB"), (8192, "8TB")]
        let best = candidates.min { abs($0.0 - decimalGB) < abs($1.0 - decimalGB) }
        guard let best = best, abs(best.0 - decimalGB) / best.0 < 0.12 else { return "—" }
        return best.1
    }
}

struct BatterySnapshot {
    var isPresent = false
    var designCapacity = 0
    var nominalCapacity = 0
    var rawMaxCapacity = 0
    var remainingCapacity = 0
    var percent: Double = 0
    var cycleCount = 0
    var designCycleCount = 1000
    var temperature: Double? = nil
    /// 电池组额定电压（V）。Intel 机型通常由 IORegistry 的 DesignVoltage 直接给出；
    /// Apple Silicon 不提供该键，此时为 nil，不能假设成某个固定值。
    var designVoltage: Double? = nil
    var voltage: Double = 0
    var amperage: Double = 0
    var isCharging = false
    var isPluggedIn = false
    var isFullyCharged = false
    var permanentFailure = false
    var batteryInstalled = true
    var serialNumber: String = "—"
    var manufacturer: String = "—"
    /// 电池计量芯片型号（如 bq40z651）。Apple 不公开电芯制造商，但芯片型号是真实可读的。
    var gaugeModel: String = ""
    var timeToEmpty: Int? = nil
    var timeToFull: Int? = nil
    var adapterWatts: Int? = nil
    var adapterName: String? = nil
    var adapterManufacturer: String? = nil

    /// 设计容量与当前满充容量之比。
    /// 口径与 macOS「系统设置 → 电池 → 电池健康 → 最大容量」一致：
    /// 使用 AppleRawMaxCapacity ÷ DesignCapacity。
    /// （实测：设计 6075 mAh、AppleRawMax 5441 mAh → 89.6%，系统显示 90%；
    ///  若误用 NominalChargeCapacity 5591 mAh 会得到 92%，与系统不符。）
    var healthPercent: Double? {
        guard designCapacity > 0 else { return nil }
        let source = rawMaxCapacity > 0 ? rawMaxCapacity : nominalCapacity
        guard source > 0 else { return nil }
        return min(100, Double(source) / Double(designCapacity) * 100)
    }

    var healthCapacity: Int {
        rawMaxCapacity > 0 ? rawMaxCapacity : nominalCapacity
    }

    var cycleProgress: Double {
        guard designCycleCount > 0 else { return 0 }
        return min(1, Double(cycleCount) / Double(designCycleCount))
    }

    /// 健康度分级。全 App 唯一口径，避免各页面用 85/80/90 等不同阈值导致自相矛盾。
    /// 80% 是 Apple 对「建议检修」的官方界限。
    var healthGrade: HealthGrade {
        guard let health = healthPercent else { return .unknown }
        switch health {
        case 90...: return .excellent
        case 80..<90: return .good
        case 70..<80: return .fair
        default: return .service
        }
    }
}

enum HealthGrade {
    case excellent, good, fair, service, unknown

    var title: String {
        switch self {
        case .excellent: return T("优秀", "Excellent")
        case .good: return T("良好", "Good")
        case .fair: return T("一般", "Fair")
        case .service: return T("建议检修", "Service Recommended")
        case .unknown: return T("不可用", "Unavailable")
        }
    }

    /// 0 = 不可用，1...4 递增
    var level: Int {
        switch self {
        case .unknown: return 0
        case .service: return 1
        case .fair: return 2
        case .good: return 3
        case .excellent: return 4
        }
    }
}

struct MacSystemInfo {
    var modelIdentifier: String = "—"
    var modelName: String = "—"
    var marketingName: String = "—"
    var modelNumber: String = ""
    /// 实际 Part Number（如 Z17G000NALL/A），来自系统报告，反映 CTO 配置
    var partNumber: String = ""
    var serialNumber: String = "—"
    var serialValid: Bool = false

    var chipName: String = "—"
    var architecture: String = "—"
    var isAppleSilicon = false
    var physicalCores: Int = 0
    var logicalCores: Int = 0
    var performanceCores: Int = 0
    var efficiencyCores: Int = 0
    var memoryGB: Int = 0
    var memoryDescription: String = ""
    var gpuName: String = "—"
    /// Apple Silicon 集成 GPU 的核心数（system_profiler sppci_cores）
    var gpuCores: Int = 0
    var isLowPowerMode = false
    var uptime: TimeInterval = 0

    var osVersion: String = "—"
    var osBuild: String = "—"
    var hardwareModel: String = "—"
    var systemUptimeText: String = "—"

    var activationLock: Bool? = nil
    var fileVault: Bool? = nil
    var sipEnabled: Bool? = nil
    var gatekeeperEnabled: Bool? = nil
    var mdmEnrolled: Bool? = nil
    var remoteManagement: Bool? = nil
    var secureBootInfo: String? = nil
    var panicLogCount: Int = 0
    /// 崩溃日志目录是否可读。不可读时必须显示"无法读取"，不能显示"无记录"。
    var panicScanAvailable: Bool = false
    var lastPanicDate: Date? = nil
    var isRefurbished: Bool? = nil

    var display = DisplayInfo()
    var storage = StorageInfo()
    var assetTag: String = ""

    // MARK: - 冗余数据源（用于一致性核验）
    // 同一事实从两条独立通路读取，任一处被改写都会出现不一致。
    // 这是"改机型、刷序列号"这类操作唯一可靠的破绽。

    /// IOKit IOPlatformExpertDevice 读到的序列号
    var serialFromIOKit: String? = nil
    /// sysctl hw.model 读到的机型标识
    var modelFromSysctl: String? = nil
    /// sysctl machdep.cpu.brand_string 读到的芯片名
    var chipFromSysctl: String? = nil
    /// sysctl hw.memsize 读到的内存字节数
    var memoryBytesFromSysctl: Int = 0

    var scannedAt = Date()
    var isScanning = false
}

extension MacSystemInfo {
    var modelDisplayName: String {
        marketingName.isEmpty ? modelName : marketingName
    }

    var chipDescription: String {
        var parts: [String] = [chipName]
        if performanceCores > 0 && efficiencyCores > 0 {
            parts.append(T("\(performanceCores) 性能核 + \(efficiencyCores) 能效核",
                           "\(performanceCores)P + \(efficiencyCores)E cores"))
        } else if physicalCores > 0 {
            parts.append(T("\(physicalCores) 核", "\(physicalCores) cores"))
        }
        return parts.joined(separator: " · ")
    }
}
