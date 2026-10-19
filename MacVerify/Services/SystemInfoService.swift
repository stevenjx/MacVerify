// Services/SystemInfoService.swift
import Foundation
import AppKit
import IOKit
import CoreGraphics
import Combine

final class SystemInfoStore: ObservableObject {
    @Published private(set) var info = MacSystemInfo()
    @Published private(set) var isScanning = false

    private let scanQueue = DispatchQueue(label: "macverify.system.scan", qos: .userInitiated)

    init() {
        refresh()
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        scanQueue.async { [weak self] in
            guard let self = self else { return }
            let collected = self.collect()
            DispatchQueue.main.async {
                self.info = collected
                self.isScanning = false
            }
        }
    }

    // MARK: - 采集

    private func collect() -> MacSystemInfo {
        var data = MacSystemInfo()

        data.modelIdentifier = Sysctl.string("hw.model") ?? "—"
        data.hardwareModel = data.modelIdentifier
        if let entry = MacModelCatalog.entry(for: data.modelIdentifier) {
            data.modelName = entry.name
            data.marketingName = entry.name
            data.modelNumber = entry.modelNumber ?? ""
        } else {
            data.modelName = MacModelCatalog.fallbackName(for: data.modelIdentifier)
            data.marketingName = data.modelName
        }

        data.serialNumber = platformSerialNumber() ?? "—"
        data.serialValid = isValidSerial(data.serialNumber)

        let brand = Sysctl.string("machdep.cpu.brand_string") ?? ""
        data.chipName = brand.isEmpty ? "—" : brand
        data.isAppleSilicon = brand.hasPrefix("Apple")

        #if arch(arm64)
        data.architecture = "Apple Silicon"
        #else
        data.architecture = "Intel"
        #endif

        data.logicalCores = Sysctl.int("hw.logicalcpu") ?? ProcessInfo.processInfo.processorCount
        data.physicalCores = Sysctl.int("hw.physicalcpu") ?? data.logicalCores

        if data.isAppleSilicon {
            data.performanceCores = Sysctl.int("hw.perflevel0.physicalcpu") ?? 0
            data.efficiencyCores = Sysctl.int("hw.perflevel1.physicalcpu") ?? 0
        }

        let memoryBytes = Sysctl.int("hw.memsize") ?? 0
        data.memoryGB = Int((Double(memoryBytes) / 1_073_741_824).rounded())
        data.memoryDescription = data.memoryGB > 0 ? "\(data.memoryGB) GB" : "—"

        data.gpuName = gpuName(fallback: data.chipName)
        data.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        data.uptime = ProcessInfo.processInfo.systemUptime
        data.systemUptimeText = Self.uptimeText(data.uptime)

        let os = ProcessInfo.processInfo.operatingSystemVersion
        data.osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        data.osBuild = Sysctl.string("kern.osversion") ?? "—"

        data.storage.totalGB = Int((Double(volumeCapacity()) / 1_000_000_000).rounded())
        data.display = collectDisplay()
        data.storage = collectStorage(base: data.storage)

        // 安全与合规状态（调用系统工具，只读）
        data.activationLock = activationLockStatus()
        data.fileVault = Self.fileVaultStatus()
        data.sipEnabled = Self.sipStatus()
        data.gatekeeperEnabled = Self.gatekeeperStatus()
        data.mdmEnrolled = Self.mdmStatus()
        data.remoteManagement = Self.remoteManagementStatus()

        let panics = Self.panicLogs()
        data.panicLogCount = panics.count
        data.lastPanicDate = panics.last

        if data.storage.deviceName.isEmpty || data.storage.deviceName == "—" {
            data.storage.deviceName = Self.rootDiskName()
        }
        data.scannedAt = Date()
        return data
    }

    // MARK: - 序列号 / 内存

    private func platformSerialNumber() -> String? {
        let service = IOKit.firstService(matching: "IOPlatformExpertDevice")
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let serial = IOKit.property(service, kIOPlatformSerialNumberKey as String) as? String else { return nil }
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isValidSerial(_ serial: String) -> Bool {
        let length = serial.trimmingCharacters(in: .whitespacesAndNewlines).count
        return length == 10 || length == 12
    }

    private func volumeCapacity() -> Int64 {
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey]),
           let capacity = values.volumeTotalCapacity {
            return Int64(capacity)
        }
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let size = attributes[.systemSize] as? NSNumber {
            return size.int64Value
        }
        return 0
    }

    // MARK: - GPU

    private func gpuName(fallback: String) -> String {
        var names: [String] = []
        IOKit.forEachService(matching: "IOPCIDevice") { service in
            guard let modelData = IOKit.property(service, "model") as? Data,
                  let raw = String(data: modelData, encoding: .ascii) else { return }
            let name = raw.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let upper = name.uppercased()
            let isGraphics = upper.contains("RADEON") || upper.contains("INTEL") || upper.contains("AMD") || upper.contains("NVIDIA")
            if isGraphics && !names.contains(name) { names.append(name) }
        }
        if names.isEmpty {
            return fallback.isEmpty || fallback == "—" ? "—" : fallback
        }
        return names.joined(separator: " + ")
    }

    // MARK: - 显示器

    private func collectDisplay() -> DisplayInfo {
        var display = DisplayInfo()
        let mainID = CGMainDisplayID()
        display.isBuiltin = CGDisplayIsBuiltin(mainID) != 0
        display.vendorID = Int(CGDisplayVendorNumber(mainID))
        display.modelID = Int(CGDisplayModelNumber(mainID))
        display.serialNumber = CGDisplaySerialNumber(mainID)
        display.pixelWidth = CGDisplayPixelsWide(mainID)
        display.pixelHeight = CGDisplayPixelsHigh(mainID)

        // 取所有可用模式中的最大像素尺寸作为面板原生分辨率
        if let modes = CGDisplayCopyAllDisplayModes(mainID, nil) as? [CGDisplayMode] {
            var native = (width: 0, height: 0)
            for mode in modes where mode.pixelWidth * mode.pixelHeight > native.width * native.height {
                native = (mode.pixelWidth, mode.pixelHeight)
            }
            if native.width > 0 {
                display.pixelWidth = native.width
                display.pixelHeight = native.height
            }
        }

        let sizeMM = CGDisplayScreenSize(mainID)
        if sizeMM.width > 0, sizeMM.height > 0 {
            let width = Double(sizeMM.width) / 25.4
            let height = Double(sizeMM.height) / 25.4
            let diagonal = (width * width + height * height).squareRoot()
            if diagonal > 5, diagonal < 40 {
                display.inches = (diagonal * 10).rounded() / 10
            }
        }

        if let mode = CGDisplayCopyDisplayMode(mainID) {
            display.refreshRate = mode.refreshRate
        }

        if let screen = NSScreen.main {
            display.name = screen.localizedName
            display.scale = screen.backingScaleFactor
            if let space = screen.colorSpace {
                display.colorSpaceName = space.localizedName ?? "—"
            }
        }

        display.edid = EDIDReader.read(preferredVendor: display.vendorID, model: display.modelID)
        return display
    }

    // MARK: - 存储

    private func collectStorage(base: StorageInfo) -> StorageInfo {
        var storage = base
        let rootDisk = Self.rootDiskBSDName()

        // 从整盘 IOMedia 向上查找持有统计数据的节点（Apple Silicon 上为 APFS 容器，Intel 上可能为 IOBlockStorageDriver）
        let media = rootDisk.isEmpty ? 0 : IOServiceGetMatchingService(0, IOBSDNameMatching(0, 0, rootDisk))
        if media != 0 {
            var current = media
            var owned = false
            for _ in 0..<6 {
                if let statistics = IOKit.property(current, "Statistics") as? [String: Any],
                   let read = statistics["Bytes (Read)"] as? UInt64,
                   let written = statistics["Bytes (Write)"] as? UInt64 {
                    storage.readBytes = read
                    storage.writtenBytes = written
                    storage.statisticsAvailable = true
                    break
                }
                var parent: io_object_t = 0
                guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS, parent != 0 else { break }
                if owned { IOObjectRelease(current) }
                current = parent
                owned = true
            }
            if owned { IOObjectRelease(current) }
            IOObjectRelease(media)
        }

        // SMART 数据（Apple Silicon 上多数机型受限，缺失时如实显示不可用）
        for className in ["AppleNVMeSMARTInterface", "IONVMeSMARTInterface"] {
            let service = IOKit.firstService(matching: className)
            guard service != 0 else { continue }
            let properties = IOKit.properties(service)
            IOObjectRelease(service)
            guard !properties.isEmpty else { continue }

            storage.smartAvailable = true
            if let used = properties["Percentage Used"] as? Int {
                storage.smartPercentageUsed = used
                storage.smartHealthPercent = max(0, min(100, 100 - used))
            }
            if let spare = properties["Available Spare"] as? Int {
                storage.smartAvailableSpare = spare
            }
            if let warning = properties["Critical Warning"] as? Int {
                storage.smartCriticalWarning = warning
            }
            if let temperature = properties["Temperature"] as? Int {
                storage.smartTemperature = Double(temperature)
            }
            if !storage.statisticsAvailable {
                if let units = properties["Data Units Read"] as? UInt64, let writtenUnits = properties["Data Units Written"] as? UInt64 {
                    storage.readBytes = units * 512_000
                    storage.writtenBytes = writtenUnits * 512_000
                    storage.statisticsAvailable = true
                }
            }
            break
        }

        // 通过 diskutil 补充介质名称（Apple 原厂 SSD 会显示为 APPLE SSD APxxxx）
        if !rootDisk.isEmpty, storage.deviceName == rootDisk || storage.deviceName == "—" || storage.deviceName.isEmpty {
            if let media = Self.mediaName(forDisk: rootDisk) {
                storage.deviceName = media
            }
        }

        return storage
    }

    /// 读取真实介质名称；APFS 容器需要顺着物理存储找到底层磁盘
    private static func mediaName(forDisk bsd: String) -> String? {
        if let name = diskutilValue(bsd, key: "MediaName"), !name.isEmpty {
            return name
        }
        guard let info = diskutilInfo(bsd),
              let stores = info["APFSPhysicalStores"] as? [[String: Any]],
              let store = stores.first?["APFSPhysicalStore"] as? String else { return nil }
        var physical = store
        if let range = physical.range(of: "s\\d", options: .regularExpression) {
            physical = String(physical[..<range.lowerBound])
        }
        if let name = diskutilValue(physical, key: "MediaName"), !name.isEmpty {
            return name
        }
        return nil
    }

    private static func diskutilValue(_ bsd: String, key: String) -> String? {
        guard let info = diskutilInfo(bsd) else { return nil }
        let value = info[key] as? String
        return value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func diskutilInfo(_ bsd: String) -> [String: Any]? {
        guard let output = Shell.run("/usr/sbin/diskutil", ["info", "-plist", bsd], timeout: 5),
              let data = output.data(using: .utf8) else { return nil }
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return plist as? [String: Any]
    }

    private static func rootDiskBSDName() -> String {
        var stats = statfs()
        guard statfs("/", &stats) == 0 else { return "" }
        let mountSource = withUnsafeBytes(of: &stats.f_mntfromname) { buffer -> String in
            let bytes = buffer.bindMemory(to: CChar.self)
            return String(cString: bytes.baseAddress!)
        }
        // /dev/disk3s1s1 -> disk3
        guard let last = mountSource.split(separator: "/").last else { return "" }
        var name = String(last)
        if let range = name.range(of: "s\\d", options: .regularExpression) {
            name = String(name[..<range.lowerBound])
        }
        return name
    }

    private static func rootDiskName() -> String {
        let bsd = rootDiskBSDName()
        guard !bsd.isEmpty else { return "—" }
        let media = IOServiceGetMatchingService(0, IOBSDNameMatching(0, 0, bsd))
        guard media != 0 else { return bsd }
        defer { IOObjectRelease(media) }

        var current = media
        var owned = false
        for _ in 0..<6 {
            if let name = IOKit.property(current, "Product Name") as? String, !name.isEmpty {
                if owned { IOObjectRelease(current) }
                return name
            }
            var parent: io_object_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS, parent != 0 else {
                if owned { IOObjectRelease(current) }
                break
            }
            if owned { IOObjectRelease(current) }
            current = parent
            owned = true
        }
        if owned { IOObjectRelease(current) }
        return bsd
    }

    // MARK: - 安全状态

    private func activationLockStatus() -> Bool? {
        guard let output = Shell.run("/usr/sbin/system_profiler", ["SPHardwareDataType"], timeout: 6) else {
            return nil
        }
        let lower = output.lowercased()
        if lower.contains("activation lock status: enabled") { return true }
        if lower.contains("activation lock status: disabled") { return false }
        return nil
    }

    private static func fileVaultStatus() -> Bool? {
        guard let output = Shell.run("/usr/bin/fdesetup", ["status"]) else { return nil }
        if output.contains("FileVault is On") { return true }
        if output.contains("FileVault is Off") { return false }
        return nil
    }

    private static func sipStatus() -> Bool? {
        guard let output = Shell.run("/usr/bin/csrutil", ["status"]) else { return nil }
        if output.lowercased().contains("status: enabled") { return true }
        if output.lowercased().contains("status: disabled") { return false }
        return nil
    }

    private static func gatekeeperStatus() -> Bool? {
        guard let output = Shell.run("/usr/sbin/spctl", ["--status"]) else { return nil }
        if output.lowercased().contains("assessments enabled") { return true }
        if output.lowercased().contains("assessments disabled") { return false }
        return nil
    }

    private static func mdmStatus() -> Bool? {
        if let output = Shell.run("/usr/bin/profiles", ["status", "-type", "enrollment"]) {
            let lower = output.lowercased()
            if lower.contains("mdm enrollment: yes") || lower.contains("enrolled via dep: yes") { return true }
            if lower.contains("mdm enrollment: no") { return false }
        }
        let managedPath = "/Library/Managed Preferences/com.apple.RemoteManagement.plist"
        if let dictionary = NSDictionary(contentsOfFile: managedPath) as? [String: Any],
           let services = dictionary["ActiveServices"] as? [Any], !services.isEmpty {
            return true
        }
        return nil
    }

    private static func remoteManagementStatus() -> Bool? {
        let path = "/Library/Managed Preferences/com.apple.RemoteManagement.plist"
        if FileManager.default.fileExists(atPath: path) { return true }
        return nil
    }

    private static func panicLogs() -> [Date] {
        var dates: [Date] = []
        let directories = [
            "/Library/Logs/DiagnosticReports",
            (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/DiagnosticReports")
        ]
        for directory in directories {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for file in files where file.hasSuffix(".panic") || file.contains(".panic.") {
                let path = (directory as NSString).appendingPathComponent(file)
                if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                   let date = attributes[.creationDate] as? Date {
                    dates.append(date)
                }
            }
        }
        return dates.sorted()
    }

    private static func uptimeText(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - EDID 解析

enum EDIDReader {
    /// 从 IODisplayConnect 读取真实 EDID，失败返回 nil（不猜测）
    static func read(preferredVendor: Int, model: Int) -> EDIDInfo? {
        var candidates: [EDIDInfo] = []

        IOKit.forEachService(matching: "IODisplayConnect") { service in
            guard let data = IOKit.property(service, "IODisplayEDID") as? Data, data.count >= 128 else { return }
            if let parsed = parse(data) { candidates.append(parsed) }
        }

        if candidates.isEmpty {
            IOKit.forEachService(matching: "AppleCLCD2") { service in
                guard let data = IOKit.property(service, "IODisplayEDID") as? Data, data.count >= 128 else { return }
                if let parsed = parse(data) { candidates.append(parsed) }
            }
        }

        if candidates.count == 1 { return candidates.first }
        if let match = candidates.first(where: { $0.productCode == model }) { return match }
        return candidates.first
    }

    static func parse(_ data: Data) -> EDIDInfo? {
        let bytes = [UInt8](data)
        guard bytes.count >= 128, bytes[0] == 0x00, bytes[1] == 0xFF, bytes[2] == 0xFF else { return nil }

        let manufacturerID = (Int(bytes[8]) << 8) | Int(bytes[9])
        let letters = [
            Character(UnicodeScalar(((manufacturerID >> 10) & 0x1F) + 64)!),
            Character(UnicodeScalar(((manufacturerID >> 5) & 0x1F) + 64)!),
            Character(UnicodeScalar((manufacturerID & 0x1F) + 64)!)
        ]

        let product = Int(bytes[10]) | (Int(bytes[11]) << 8)
        let serial = UInt32(bytes[12]) | (UInt32(bytes[13]) << 8) | (UInt32(bytes[14]) << 16) | (UInt32(bytes[15]) << 24)
        let week = Int(bytes[16])
        let year = Int(bytes[17]) + 1990

        return EDIDInfo(
            manufacturerID: manufacturerID,
            manufacturerName: String(letters),
            productCode: product,
            serialNumber: serial,
            year: year,
            week: week
        )
    }
}
