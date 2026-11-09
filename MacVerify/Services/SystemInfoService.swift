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
    /// 每次启动只自动存一份快照，避免反复点扫描把历史刷满
    private var hasSavedLaunchSnapshot = false

    init() {
        refresh()
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        scanQueue.async { [weak self] in
            guard let self = self else { return }
            let collected = self.collect()
            // 首次扫描后自动留一份快照，供「两次对比」使用；不需要额外点击。
            let shouldSave = !self.hasSavedLaunchSnapshot
            if shouldSave { self.hasSavedLaunchSnapshot = true }
            let snapshot = shouldSave
                ? ScanSnapshot.make(info: collected, battery: BatteryStore.readBattery(),
                                    source: T("本机扫描", "Local scan"))
                : nil
            DispatchQueue.main.async {
                self.info = collected
                self.isScanning = false
                if let snapshot = snapshot { ScanHistoryStore.append(snapshot) }
            }
        }
    }

    // MARK: - 采集

    /// 同步采集一次。供报告导出与命令行自检使用。
    func collectNow() -> MacSystemInfo {
        collect()
    }

    private func collect() -> MacSystemInfo {
        var data = MacSystemInfo()

        // 一次 system_profiler -json 同时拿到机型编号、序列号、激活锁、芯片、GPU 核心数。
        // 用 JSON 而不是文本：文本会随系统语言本地化（中文系统输出「激活锁状态：已停用」），
        // 按英文关键字匹配会在中文环境下静默失败。
        let hardware = Self.hardwareOverview()
        let displays = Self.displayOverview()

        data.modelIdentifier = hardware["machine_model"] as? String
            ?? Sysctl.string("hw.model") ?? "—"
        data.hardwareModel = data.modelIdentifier
        if let entry = MacModelCatalog.entry(for: data.modelIdentifier) {
            data.modelName = entry.name
            data.marketingName = entry.name
            data.modelNumber = entry.modelNumber ?? ""
        } else {
            data.modelName = MacModelCatalog.fallbackName(for: data.modelIdentifier)
            data.marketingName = data.modelName
        }
        // 系统报告里的 "Model Number"(如 Z17G000NALL/A) 是 Part Number，反映 CTO 配置；
        // 机型表里的 A2779 是机壳型号。两者含义不同，不能互相覆盖。
        data.partNumber = (hardware["model_number"] as? String) ?? ""

        let reportedSerial = hardware["serial_number"] as? String
        let iokitSerial = platformSerialNumber()
        data.serialFromIOKit = iokitSerial
        data.serialNumber = reportedSerial ?? iokitSerial ?? "—"
        data.serialValid = isValidSerial(data.serialNumber)

        let brand = (hardware["chip_type"] as? String) ?? Sysctl.string("machdep.cpu.brand_string") ?? ""
        data.chipName = brand.isEmpty ? "—" : brand
        data.isAppleSilicon = brand.hasPrefix("Apple")
        data.modelFromSysctl = Sysctl.string("hw.model")
        data.chipFromSysctl = Sysctl.string("machdep.cpu.brand_string")

        #if arch(arm64)
        data.architecture = data.isAppleSilicon ? "Apple Silicon" : "Intel"
        #else
        // 在 Apple Silicon 上以 Rosetta 运行 x86_64 切片时，arch(arm64) 为 false，
        // 必须按芯片名判断，否则会把 M 系列误报成 Intel。
        data.architecture = data.isAppleSilicon ? "Apple Silicon (Rosetta)" : "Intel"
        #endif

        data.logicalCores = Sysctl.int("hw.logicalcpu") ?? ProcessInfo.processInfo.processorCount
        data.physicalCores = Sysctl.int("hw.physicalcpu") ?? data.logicalCores

        if data.isAppleSilicon {
            data.performanceCores = Sysctl.int("hw.perflevel0.physicalcpu") ?? 0
            data.efficiencyCores = Sysctl.int("hw.perflevel1.physicalcpu") ?? 0
        }

        let memoryBytes = Sysctl.int("hw.memsize") ?? 0
        data.memoryBytesFromSysctl = memoryBytes
        data.memoryGB = Int((Double(memoryBytes) / 1_073_741_824).rounded())
        data.memoryDescription = data.memoryGB > 0 ? "\(data.memoryGB) GB" : "—"

        data.gpuName = Self.gpuName(displayReport: displays, fallback: data.chipName)
        data.gpuCores = Self.gpuCores(displayReport: displays)
        data.gpus = Self.gpuList(displayReport: displays)
        data.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        data.uptime = ProcessInfo.processInfo.systemUptime
        data.systemUptimeText = Self.uptimeText(data.uptime)

        let os = ProcessInfo.processInfo.operatingSystemVersion
        data.osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        data.osBuild = Sysctl.string("kern.osversion") ?? "—"

        data.display = collectDisplay(report: displays)
        data.storage = collectStorage(base: StorageInfo())
        data.peripherals = PeripheralsService.collect()

        // 安全与合规状态（调用系统工具，只读）
        data.activationLock = Self.activationLockStatus(from: hardware)
        data.fileVault = Self.fileVaultStatus()
        data.sipEnabled = Self.sipStatus()
        data.gatekeeperEnabled = Self.gatekeeperStatus()
        data.mdmEnrolled = Self.mdmStatus()
        data.remoteManagement = Self.remoteManagementStatus()

        let panics = Self.panicLogs()
        data.panicScanAvailable = panics.readable
        data.panicLogCount = panics.dates.count
        data.lastPanicDate = panics.dates.last

        data.scannedAt = Date()
        return data
    }

    // MARK: - system_profiler JSON

    private static func jsonReport(_ dataType: String) -> [[String: Any]] {
        guard let output = Shell.run("/usr/sbin/system_profiler", ["-json", dataType], timeout: 8),
              let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = root[dataType] as? [[String: Any]] else { return [] }
        return array
    }

    /// SPHardwareDataType 只有一个元素
    private static func hardwareOverview() -> [String: Any] {
        jsonReport("SPHardwareDataType").first ?? [:]
    }

    /// SPDisplaysDataType：可能是集成 GPU，也可能有外接显卡（多个元素）
    private static func displayOverview() -> [[String: Any]] {
        jsonReport("SPDisplaysDataType")
    }

    private static func gpuName(displayReport: [[String: Any]], fallback: String) -> String {
        for entry in displayReport {
            if let model = entry["sppci_model"] as? String, !model.isEmpty { return model }
        }
        return fallback.isEmpty || fallback == "—" ? "—" : fallback
    }

    private static func gpuCores(displayReport: [[String: Any]]) -> Int {
        for entry in displayReport {
            if let raw = entry["sppci_cores"] as? String, let cores = Int(raw) { return cores }
            if let cores = entry["sppci_cores"] as? Int { return cores }
        }
        return 0
    }

    /// 逐块列出 GPU。Intel 机型会返回「核显 + 独显」两条，界面必须都显示出来。
    private static func gpuList(displayReport: [[String: Any]]) -> [GPUInfo] {
        displayReport.compactMap { entry in
            let name = ((entry["sppci_model"] as? String)
                ?? (entry["_name"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            var gpu = GPUInfo()
            gpu.name = name
            if let raw = entry["sppci_cores"] as? String {
                gpu.cores = Int(raw) ?? 0
            } else if let cores = entry["sppci_cores"] as? Int {
                gpu.cores = cores
            }
            gpu.bus = entry["sppci_bus"] as? String ?? ""
            gpu.vendor = entry["spdisplays_vendor"] as? String ?? ""
            return gpu
        }
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
        // Apple 序列号历史上出现过 10 / 11 / 12 位三种长度（2021 年前的 11 位很常见），
        // 只校验长度会误报，因此这里只排除明显异常的空值与非字母数字。
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (10...12).contains(trimmed.count) else { return false }
        let allowed = CharacterSet.alphanumerics
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - 显示器

    private func collectDisplay(report: [[String: Any]]) -> DisplayInfo {
        var display = DisplayInfo()
        let mainID = CGMainDisplayID()
        display.isBuiltin = CGDisplayIsBuiltin(mainID) != 0
        display.vendorID = Int(CGDisplayVendorNumber(mainID))
        display.modelID = Int(CGDisplayModelNumber(mainID))
        display.serialNumber = CGDisplaySerialNumber(mainID)
        display.pixelWidth = CGDisplayPixelsWide(mainID)
        display.pixelHeight = CGDisplayPixelsHigh(mainID)

        // 取所有可用模式中的最大像素尺寸作为面板原生分辨率
        // （当前模式通常是缩放后的逻辑分辨率，不能当原生值）
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
        display.panel = Self.panelIdentity(from: report)
        return display
    }

    /// 从 SPDisplaysDataType 里取当前主显示器的面板身份。
    /// Apple Silicon 不公开 EDID 原始块，但 product-id / vendor-id / serial-number 仍然可用，
    /// 是判断「面板是否被换过」最直接的依据。
    private static func panelIdentity(from report: [[String: Any]]) -> PanelIdentity? {
        var fallback: PanelIdentity?
        for gpu in report {
            guard let screens = gpu["spdisplays_ndrvs"] as? [[String: Any]] else { continue }
            for screen in screens {
                guard let identity = parsePanel(screen) else { continue }
                // 优先返回内建屏
                if screen["spdisplays_connection_type"] as? String == "spdisplays_internal" {
                    return identity
                }
                if fallback == nil { fallback = identity }
            }
        }
        return fallback
    }

    private static func parsePanel(_ screen: [String: Any]) -> PanelIdentity? {
        var identity = PanelIdentity()
        var hasAny = false

        if let vendor = screen["_spdisplays_display-vendor-id"] as? String {
            // 该字段是十六进制字符串（例："610" 表示 0x610 = Apple）
            if let value = Int(vendor, radix: 16) { identity.vendorID = value; hasAny = true }
        }
        if let product = screen["_spdisplays_display-product-id"] as? String {
            if let value = Int(product, radix: 16) { identity.productID = value; hasAny = true }
        }
        if let serial = screen["_spdisplays_display-serial-number"] as? String {
            if let value = UInt64(serial, radix: 16) { identity.serialNumber = value; hasAny = true }
        }
        if let week = screen["_spdisplays_display-week"] as? String, let value = Int(week) {
            identity.week = value
        }
        if let year = screen["_spdisplays_display-year"] as? String, let value = Int(year) {
            identity.year = value
        }
        identity.typeName = Self.decodeDisplayType(screen["spdisplays_display_type"] as? String)
        identity.connectionType = Self.decodeConnection(screen["spdisplays_connection_type"] as? String)
        return hasAny ? identity : nil
    }

    /// 系统报告里的枚举值是本地化无关的固定 token
    private static func decodeDisplayType(_ token: String?) -> String {
        guard let token = token else { return "" }
        let table: [String: String] = [
            "spdisplays_built-in-liquid-retina-xdr": "Liquid Retina XDR",
            "spdisplays_built-in-retina": "Retina",
            "spdisplays_built-in": T("内建", "Built-in"),
            "spdisplays_lcd": "LCD",
            "spdisplays_led": "LED",
            "spdisplays_crt": "CRT",
            "spdisplays_projector": T("投影", "Projector")
        ]
        if let name = table[token] { return name }
        if token.hasPrefix("spdisplays_") {
            return token.replacingOccurrences(of: "spdisplays_", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
        return token
    }

    private static func decodeConnection(_ token: String?) -> String {
        switch token {
        case "spdisplays_internal": return T("内建", "Internal")
        case "spdisplays_displayport": return "DisplayPort"
        case "spdisplays_hdmi": return "HDMI"
        case "spdisplays_thunderbolt": return "Thunderbolt"
        case "spdisplays_vga": return "VGA"
        case "spdisplays_dvi": return "DVI"
        default: return token?.replacingOccurrences(of: "spdisplays_", with: "") ?? ""
        }
    }

    // MARK: - 存储

    private func collectStorage(base: StorageInfo) -> StorageInfo {
        var storage = base
        let rootDisk = Self.rootDiskBSDName()

        // 物理介质容量 / 名称。必须走物理盘（disk0），而不是根卷（disk3）：
        // 根卷 994.7GB、物理盘 1000.6GB，用根卷会把 1TB 机器显示成 995GB。
        if !rootDisk.isEmpty {
            let physical = Self.physicalStore(forDisk: rootDisk) ?? rootDisk
            if let info = Self.diskutilInfo(physical) {
                if let size = info["TotalSize"] as? Int64, size > 0 {
                    storage.physicalBytes = UInt64(size)
                    storage.diskSizeFromDiskutil = UInt64(size)
                } else if let size = info["Size"] as? Int64, size > 0 {
                    storage.physicalBytes = UInt64(size)
                    storage.diskSizeFromDiskutil = UInt64(size)
                }
                let name = (info["MediaName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !name.isEmpty { storage.deviceName = name }
                storage.isInternalDisk = info["Internal"] as? Bool
            }
            storage.diskSizeFromIOMedia = Self.ioMediaSize(forDisk: physical)
        }

        // 从整盘 IOMedia 向上查找持有统计数据的节点（Apple Silicon 上为 APFS 容器，Intel 上可能为 IOBlockStorageDriver）
        let media = rootDisk.isEmpty ? 0 : IOServiceGetMatchingService(0, IOBSDNameMatching(0, 0, rootDisk))
        if media != 0 {
            var current = media
            var owned = false
            for _ in 0..<6 {
                if let statistics = IOKit.property(current, "Statistics") as? [String: Any],
                   let read = statistics["Bytes (Read)"] as? UInt64,
                   let written = statistics["Bytes (Write)"] as? UInt64,
                   read > 0 || written > 0 {
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

        // SMART：先走 IOKit（Intel 机型有 NVMe SMART 接口），再走 diskutil。
        // 实测：diskutil info -plist 在现代 macOS 上会返回完整的 NVMe SMART 键值
        // （SMARTDeviceSpecificKeysMayVaryNotGuaranteed），这是 Apple Silicon 上唯一可用且完整的通路。
        Self.collectSmartFromIOKit(into: &storage)
        if !storage.smartAvailable {
            if let info = Self.diskutilInfo(Self.physicalStore(forDisk: rootDisk) ?? rootDisk) {
                Self.applySmartFromDiskutil(info, into: &storage)
            }
        }

        // 介质名兜底：物理盘取不到时再顺着 APFS 物理存储找一次
        if storage.deviceName == "—" || storage.deviceName.isEmpty {
            if let media = Self.mediaName(forDisk: rootDisk) {
                storage.deviceName = media
            }
        }

        // 物理容量兜底：diskutil 完全不可用时退回 IOMedia Size
        if storage.physicalBytes == 0 {
            storage.physicalBytes = Self.ioMediaSize(forDisk: Self.physicalStore(forDisk: rootDisk) ?? rootDisk)
        }

        return storage
    }

    // MARK: - SMART

    /// Intel 机型：IONVMeSMARTInterface / AppleNVMeSMARTInterface 直接暴露 SMART 键值。
    /// Apple Silicon 通常没有这两个类，需回落到 diskutil。
    private static func collectSmartFromIOKit(into storage: inout StorageInfo) {
        for className in ["AppleNVMeSMARTInterface", "IONVMeSMARTInterface"] {
            let service = IOKit.firstService(matching: className)
            guard service != 0 else { continue }
            let properties = IOKit.properties(service)
            IOObjectRelease(service)
            guard !properties.isEmpty else { continue }

            var found = false
            if let used = intValue(properties["Percentage Used"]) {
                storage.smartPercentageUsed = used
                storage.smartHealthPercent = max(0, min(100, 100 - used))
                found = true
            }
            if let spare = intValue(properties["Available Spare"]) {
                storage.smartAvailableSpare = spare
                found = true
            }
            if let spareThreshold = intValue(properties["Available Spare Threshold"]) {
                storage.smartSpareThreshold = spareThreshold
            }
            if let warning = intValue(properties["Critical Warning"]) {
                storage.smartCriticalWarning = warning
            }
            if let temperature = intValue(properties["Temperature"]) {
                storage.smartTemperature = celsius(fromKelvin: temperature)
            }
            if let units = uintValue(properties["Data Units Read"]) {
                storage.smartLifetimeReadBytes = units &* 512_000
                found = true
            }
            if let units = uintValue(properties["Data Units Written"]) {
                storage.smartLifetimeWrittenBytes = units &* 512_000
            }
            if let hours = intValue(properties["Power On Hours"]) { storage.smartPowerOnHours = hours }
            if let cycles = intValue(properties["Power Cycles"]) { storage.smartPowerCycles = cycles }
            if let unsafeShutdowns = intValue(properties["Unsafe Shutdowns"]) { storage.smartUnsafeShutdowns = unsafeShutdowns }
            if let mediaErrors = intValue(properties["Media Errors"]) { storage.smartMediaErrors = mediaErrors }

            if found {
                storage.smartAvailable = true
                storage.smartSource = "IOKit \(className)"
                return
            }
        }
    }

    /// 现代 macOS（Intel 与 Apple Silicon 皆然）：
    /// `diskutil info -plist <physicalDisk>` 的 SMARTDeviceSpecificKeysMayVaryNotGuaranteed
    /// 里含有完整的 NVMe SMART 字段。这是 Apple Silicon 上唯一可用的完整通路。
    private static func applySmartFromDiskutil(_ info: [String: Any], into storage: inout StorageInfo) {
        let status = (info["SMARTStatus"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let status = status, !status.isEmpty { storage.smartStatusText = status }

        guard let keys = info["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any],
              !keys.isEmpty else {
            // 有状态但无明细（部分 USB/外接盘如此），仍然算"读到了状态"
            if storage.smartStatusText != nil { storage.smartSource = "diskutil SMARTStatus" }
            return
        }

        storage.smartAvailable = true
        storage.smartSource = "diskutil SMART"

        if let used = intValue(keys["PERCENTAGE_USED"]) {
            storage.smartPercentageUsed = used
            storage.smartHealthPercent = max(0, min(100, 100 - used))
        }
        if let spare = intValue(keys["AVAILABLE_SPARE"]) { storage.smartAvailableSpare = spare }
        if let threshold = intValue(keys["AVAILABLE_SPARE_THRESHOLD"]) { storage.smartSpareThreshold = threshold }
        if let temperature = intValue(keys["TEMPERATURE"]) {
            storage.smartTemperature = celsius(fromKelvin: temperature)
        }
        if let hours = intValue(keys["POWER_ON_HOURS_0"]) { storage.smartPowerOnHours = hours }
        if let cycles = intValue(keys["POWER_CYCLES_0"]) { storage.smartPowerCycles = cycles }
        if let unsafeShutdowns = intValue(keys["UNSAFE_SHUTDOWNS_0"]) { storage.smartUnsafeShutdowns = unsafeShutdowns }
        if let mediaErrors = intValue(keys["MEDIA_ERRORS_0"]) { storage.smartMediaErrors = mediaErrors }
        if let errorLogs = intValue(keys["NUM_ERROR_INFO_LOG_ENTRIES_0"]) { storage.smartErrorLogEntries = errorLogs }
        if let commands = uintValue(keys["HOST_READ_COMMANDS_0"]) { storage.smartHostReadCommands = commands }
        if let commands = uintValue(keys["HOST_WRITE_COMMANDS_0"]) { storage.smartHostWriteCommands = commands }

        // NVMe 的 Data Units 固定按 1000 × 512 字节换算
        if let units = uintValue(keys["DATA_UNITS_READ_0"]) {
            storage.smartLifetimeReadBytes = units &* 512_000
        }
        if let units = uintValue(keys["DATA_UNITS_WRITTEN_0"]) {
            storage.smartLifetimeWrittenBytes = units &* 512_000
        }
        // 兼容旧版 diskutil 的带空格键名
        if storage.smartPercentageUsed == nil, let used = intValue(keys["Percentage Used"]) {
            storage.smartPercentageUsed = used
            storage.smartHealthPercent = max(0, min(100, 100 - used))
        }
    }

    /// NVMe 温度以开尔文记录（实测 306 → 32.9 ℃）。
    /// 若某项异常低（< 200）则已是摄氏，不再减 273；避免把 40℃ 显示成 -233℃。
    private static func celsius(fromKelvin raw: Int) -> Double? {
        guard raw > 0 else { return nil }
        let value = raw > 200 ? Double(raw) - 273.15 : Double(raw)
        guard value > -20, value < 120 else { return nil }
        return (value * 10).rounded() / 10
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let int64 = value as? Int64 { return Int(int64) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func uintValue(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let uint = value as? UInt64 { return uint }
        if let int = value as? Int, int >= 0 { return UInt64(int) }
        if let string = value as? String, let parsed = UInt64(string) { return parsed }
        return nil
    }

    /// 根卷（disk3）→ 物理存储（disk0）。APFS 容器必须顺着这个映射才能拿到真实介质。
    private static func physicalStore(forDisk bsd: String) -> String? {
        guard let info = diskutilInfo(bsd),
              let stores = info["APFSPhysicalStores"] as? [[String: Any]],
              let store = stores.first?["APFSPhysicalStore"] as? String else { return nil }
        var physical = store
        if let range = physical.range(of: "s\\d", options: .regularExpression) {
            physical = String(physical[..<range.lowerBound])
        }
        return physical.isEmpty ? nil : physical
    }

    private static func ioMediaSize(forDisk bsd: String) -> UInt64 {
        guard !bsd.isEmpty else { return 0 }
        let service = IOServiceGetMatchingService(0, IOBSDNameMatching(0, 0, bsd))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        if let size = IOKit.property(service, "Size") as? UInt64 { return size }
        if let size = IOKit.property(service, "Size") as? Int64 { return UInt64(max(0, size)) }
        return 0
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

    /// 激活锁状态来自 SPHardwareDataType 的稳定 token：
    /// "activation_lock_enabled" / "activation_lock_disabled" / "activation_lock_unknown"
    private static func activationLockStatus(from hardware: [String: Any]) -> Bool? {
        guard let token = hardware["activation_lock_status"] as? String else { return nil }
        if token.hasSuffix("_enabled") { return true }
        if token.hasSuffix("_disabled") { return false }
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

    /// 远程管理描述文件是否存在。文件不存在是确定结论（false），不是"读不到"。
    private static func remoteManagementStatus() -> Bool? {
        let path = "/Library/Managed Preferences/com.apple.RemoteManagement.plist"
        return FileManager.default.fileExists(atPath: path)
    }

    /// 内核崩溃（panic）记录。
    /// - macOS 12 及更早：`*.panic` 文件
    /// - macOS 13+：内核崩溃改为 `*.ips`，需判断 `bug_type` 是否为 210
    /// 额外扫描 Retired/ 子目录（系统会把旧报告移进去）。
    /// 返回 readable 用于区分「确实没有崩溃」与「目录读不到」——
    /// 后者绝不能显示成「无记录」。
    private static func panicLogs() -> (dates: [Date], readable: Bool) {
        var dates: [Date] = []
        var readable = false

        let roots = [
            "/Library/Logs/DiagnosticReports",
            (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/DiagnosticReports")
        ]

        for root in roots {
            for directory in [root, (root as NSString).appendingPathComponent("Retired")] {
                guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
                readable = true
                for file in files {
                    let path = (directory as NSString).appendingPathComponent(file)
                    let isPanicFile = file.hasSuffix(".panic")
                    let isIPS = file.hasSuffix(".ips")
                    guard isPanicFile || isIPS else { continue }
                    if isIPS, !Self.isKernelPanicIPS(path) { continue }
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                       let date = attributes[.creationDate] as? Date {
                        dates.append(date)
                    }
                }
            }
        }
        return (dates.sorted(), readable)
    }

    /// .ips 文件的前几 KB 是 JSON 头，内核崩溃的 bug_type 为 210
    private static func isKernelPanicIPS(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4096),
              let text = String(data: head, encoding: .utf8) else { return false }
        return text.contains("\"bug_type\":\"210\"") || text.contains("\"bug_type\" : \"210\"")
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

        // 校验和：前 128 字节之和须为 0（mod 256）。不校验会把随机数据当面板信息显示。
        let checksum = bytes[0..<128].reduce(0) { ($0 + Int($1)) & 0xFF }
        guard checksum == 0 else { return nil }

        let manufacturerID = (Int(bytes[8]) << 8) | Int(bytes[9])
        guard let a = UnicodeScalar(((manufacturerID >> 10) & 0x1F) + 64),
              let b = UnicodeScalar(((manufacturerID >> 5) & 0x1F) + 64),
              let c = UnicodeScalar((manufacturerID & 0x1F) + 64) else { return nil }
        let letters = String(Character(a)) + String(Character(b)) + String(Character(c))
        guard !letters.contains("@") || manufacturerID != 0 else { return nil }

        let product = Int(bytes[10]) | (Int(bytes[11]) << 8)
        let serial = UInt32(bytes[12]) | (UInt32(bytes[13]) << 8) | (UInt32(bytes[14]) << 16) | (UInt32(bytes[15]) << 24)
        let week = Int(bytes[16])
        let yearByte = Int(bytes[17])

        return EDIDInfo(
            manufacturerID: manufacturerID,
            manufacturerName: letters,
            productCode: product,
            serialNumber: serial,
            // year 字节为 0 表示未写入生产日期，不能算成 1990 年
            year: yearByte > 0 ? yearByte + 1990 : 0,
            week: week
        )
    }
}
