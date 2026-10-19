// Models/HardwareModels.swift
import Foundation

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
    var totalGB: Int = 0
    var deviceName: String = "—"
    var medium: String = "—"
    var readBytes: UInt64 = 0
    var writtenBytes: UInt64 = 0
    var statisticsAvailable = false
    var smartHealthPercent: Int? = nil
    var smartPercentageUsed: Int? = nil
    var smartAvailableSpare: Int? = nil
    var smartCriticalWarning: Int? = nil
    var smartTemperature: Double? = nil
    var smartAvailable = false
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
    var voltage: Double = 0
    var amperage: Double = 0
    var isCharging = false
    var isPluggedIn = false
    var isFullyCharged = false
    var permanentFailure = false
    var batteryInstalled = true
    var serialNumber: String = "—"
    var manufacturer: String = "—"
    var timeToEmpty: Int? = nil
    var timeToFull: Int? = nil
    var adapterWatts: Int? = nil
    var adapterName: String? = nil
    var adapterManufacturer: String? = nil

    /// 设计容量与当前满充容量之比（Apple 官方口径）
    var healthPercent: Double? {
        guard designCapacity > 0 else { return nil }
        let source = nominalCapacity > 0 ? nominalCapacity : rawMaxCapacity
        guard source > 0 else { return nil }
        return min(100, Double(source) / Double(designCapacity) * 100)
    }

    var healthCapacity: Int {
        nominalCapacity > 0 ? nominalCapacity : rawMaxCapacity
    }

    var cycleProgress: Double {
        guard designCycleCount > 0 else { return 0 }
        return min(1, Double(cycleCount) / Double(designCycleCount))
    }
}

struct MacSystemInfo {
    var modelIdentifier: String = "—"
    var modelName: String = "—"
    var marketingName: String = "—"
    var modelNumber: String = ""
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
    var lastPanicDate: Date? = nil
    var isRefurbished: Bool? = nil

    var display = DisplayInfo()
    var storage = StorageInfo()
    var assetTag: String = ""

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
