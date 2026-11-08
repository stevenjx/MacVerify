// Services/ReportService.swift
// 质检报告：只汇总已经采集到的实测值，不做任何推断或补值。
// 未采集到的项一律输出 null / "unavailable"，避免下游误读为 0 或 false。
import Foundation
import AppKit
import UniformTypeIdentifiers

enum ReportState: String {
    case ok
    case warning
    case critical
    case unavailable
}

struct ReportItem {
    let key: String
    let label: String
    let value: String?
    let state: ReportState
    let note: String?
}

struct ReportSection {
    let title: String
    let items: [ReportItem]
}

enum ReportService {

    // MARK: - 构建

    static func build(info: MacSystemInfo, battery: BatterySnapshot) -> (sections: [ReportSection], verdict: String, issues: Int) {
        var sections: [ReportSection] = []
        var issues = 0
        // risks = 明确不一致；confirmations = 需人工确认（不超过「不一致」的严重度）
        var risks = 0
        var confirmations = 0

        // 设备
        var device: [ReportItem] = [
            item("model_identifier", "机型标识", info.modelIdentifier, .ok),
            item("marketing_name", "营销名称", info.modelDisplayName, .ok),
            item("chassis_model", "机壳型号", emptyToNil(info.modelNumber), .ok),
            item("part_number", "配置编号", emptyToNil(info.partNumber), .ok),
            item("serial_number", "序列号", emptyToNil(info.serialNumber), info.serialValid ? .ok : .warning,
                 note: info.serialValid ? nil : "序列号长度或字符不符合 Apple 常见格式"),
            item("chip", "芯片", emptyToNil(info.chipName), .ok),
            item("cpu_cores", "CPU 核心", coresText(info), .ok),
            item("memory", "内存", info.memoryGB > 0 ? "\(info.memoryGB) GB" : nil, .ok),
            item("gpu", "图形处理器", gpuText(info), .ok),
            item("os", "macOS", "\(info.osVersion) (\(info.osBuild))", .ok),
            item("architecture", "架构", info.architecture, .ok)
        ]
        if !info.serialValid { issues += 1 }
        sections.append(ReportSection(title: "设备 / Device", items: device))
        device.removeAll()

        // 安全
        let panicValue: String? = info.panicScanAvailable ? "\(info.panicLogCount)" : nil
        let panicState: ReportState = !info.panicScanAvailable ? .unavailable : (info.panicLogCount > 0 ? .warning : .ok)
        if info.panicScanAvailable, info.panicLogCount > 0 { issues += 1 }

        let security: [ReportItem] = [
            tri("activation_lock", "激活锁", info.activationLock,
                trueState: .warning, falseState: .ok,
                trueNote: "设备与原 Apple ID 绑定，需原机主退出后才能正常使用"),
            tri("file_vault", "文件保险箱", info.fileVault, trueState: .ok, falseState: .warning,
                falseNote: "未开启全盘加密"),
            tri("sip", "系统完整性保护", info.sipEnabled, trueState: .ok, falseState: .warning,
                falseNote: "SIP 已关闭，系统可能被改动过"),
            tri("gatekeeper", "门禁", info.gatekeeperEnabled, trueState: .ok, falseState: .warning,
                falseNote: "Gatekeeper 已关闭"),
            tri("mdm", "MDM 注册", info.mdmEnrolled, trueState: .warning, falseState: .ok,
                trueNote: "设备受组织管理，可能被远程锁定或抹除"),
            item("remote_management", "远程管理配置",
                 info.remoteManagement == true ? "present" : (info.remoteManagement == false ? "absent" : nil),
                 info.remoteManagement == true ? .warning : (info.remoteManagement == false ? .ok : .unavailable)),
            ReportItem(key: "kernel_panics", label: "内核崩溃记录", value: panicValue,
                       state: panicState, note: info.panicScanAvailable ? nil : "崩溃日志目录不可读")
        ]
        for entry in security {
            if entry.state == .warning || entry.state == .critical, entry.key != "file_vault" { issues += 1 }
        }
        sections.append(ReportSection(title: "安全与合规 / Security", items: security))

        // 显示屏
        let display = info.display
        var displayItems: [ReportItem] = [
            item("display_size", "屏幕对角线（实测）", display.inches > 0 ? String(format: "%.1f inch", display.inches) : nil, .ok),
            item("display_resolution", "原生分辨率", display.pixelWidth > 0 ? "\(display.pixelWidth) x \(display.pixelHeight)" : nil, .ok),
            item("display_refresh", "当前刷新率", display.refreshRate > 0 ? String(format: "%.0f Hz", display.refreshRate) : nil, .ok),
            item("display_builtin", "内建屏幕", display.isBuiltin ? "yes" : "no", .ok)
        ]
        if let panel = display.panel {
            displayItems += [
                item("panel_vendor", "面板厂商 ID", panel.vendorText, .ok),
                item("panel_product", "面板型号 ID", panel.productText, .ok),
                item("panel_serial", "面板序列号", panel.serialText, .ok),
                item("panel_type", "面板类型", emptyToNil(panel.typeName), .ok),
                item("panel_production", "面板生产批次",
                     panel.productionText == "—" ? nil : panel.productionText, .ok,
                     note: "面板未写入生产日期")
            ]
        } else {
            displayItems.append(ReportItem(key: "panel_identity", label: "面板身份", value: nil,
                                           state: .unavailable, note: "本机未向用户态提供面板身份信息"))
            issues += 1
        }
        sections.append(ReportSection(title: "显示屏 / Display", items: displayItems))

        // 存储
        let storage = info.storage
        let storageItems: [ReportItem] = [
            item("storage_model", "磁盘型号", emptyToNil(storage.deviceName), .ok),
            item("storage_capacity", "标称容量", storage.marketingCapacity == "—" ? nil : storage.marketingCapacity, .ok),
            item("storage_physical_bytes", "物理容量（字节）",
                 storage.physicalBytes > 0 ? "\(storage.physicalBytes)" : nil, .ok),
            item("storage_read_bytes", "累计读取（字节）",
                 storage.statisticsAvailable ? "\(storage.readBytes)" : nil,
                 storage.statisticsAvailable ? .ok : .unavailable,
                 note: storage.statisticsAvailable ? nil : "本机未暴露块设备统计"),
            item("storage_written_bytes", "累计写入（字节）",
                 storage.statisticsAvailable ? "\(storage.writtenBytes)" : nil,
                 storage.statisticsAvailable ? .ok : .unavailable),
            ReportItem(key: "ssd_health", label: "SSD 剩余寿命",
                       value: storage.smartHealthPercent.map { "\($0)%" },
                       state: storage.smartHealthPercent == nil ? .unavailable
                           : (storage.smartHealthPercent! >= 80 ? .ok : (storage.smartHealthPercent! >= 50 ? .warning : .critical)),
                       note: storage.smartHealthPercent == nil ? "本机未提供 SMART 数据" : nil),
            item("smart_status", "SMART 状态", emptyToNil(storage.smartStatusText ?? "—"),
                 storage.smartStatusText == nil ? .unavailable : .ok),
            item("smart_lifetime_read", "SSD 累计读取（字节）",
                 storage.smartLifetimeReadBytes.map { "\($0)" },
                 storage.smartLifetimeReadBytes == nil ? .unavailable : .ok,
                 note: storage.smartLifetimeReadBytes == nil ? nil : "NVMe Data Units 换算，含格式化前数据"),
            item("smart_lifetime_written", "SSD 累计写入（字节）",
                 storage.smartLifetimeWrittenBytes.map { "\($0)" },
                 storage.smartLifetimeWrittenBytes == nil ? .unavailable : .ok,
                 note: storage.smartLifetimeWrittenBytes == nil ? nil : "NVMe Data Units 换算，含格式化前数据"),
            item("smart_power_on_hours", "SSD 上电时长（小时）",
                 storage.smartPowerOnHours.map { "\($0)" },
                 storage.smartPowerOnHours == nil ? .unavailable : .ok),
            item("smart_power_cycles", "SSD 上电次数",
                 storage.smartPowerCycles.map { "\($0)" },
                 storage.smartPowerCycles == nil ? .unavailable : .ok),
            ReportItem(key: "smart_unsafe_shutdowns", label: "异常断电次数",
                       value: storage.smartUnsafeShutdowns.map { "\($0)" },
                       state: storage.smartUnsafeShutdowns == nil ? .unavailable
                           : ((storage.smartUnsafeShutdowns ?? 0) > 100 ? .warning : .ok),
                       note: nil),
            ReportItem(key: "smart_media_errors", label: "介质错误次数",
                       value: storage.smartMediaErrors.map { "\($0)" },
                       state: storage.smartMediaErrors == nil ? .unavailable
                           : ((storage.smartMediaErrors ?? 0) > 0 ? .critical : .ok),
                       note: nil),
            item("smart_available_spare", "剩余备用块 (%)",
                 storage.smartAvailableSpare.map { "\($0)" },
                 storage.smartAvailableSpare == nil ? .unavailable : .ok),
            item("smart_spare_threshold", "备用块告警阈值 (%)",
                 storage.smartSpareThreshold.map { "\($0)" },
                 storage.smartSpareThreshold == nil ? .unavailable : .ok),
            item("smart_temperature", "SSD 温度 (°C)",
                 storage.smartTemperature.map { String(format: "%.1f", $0) },
                 storage.smartTemperature == nil ? .unavailable : .ok)
        ]
        if let health = storage.smartHealthPercent, health < 80 { issues += 1 }
        sections.append(ReportSection(title: "存储 / Storage", items: storageItems))

        // 电池
        var batteryItems: [ReportItem] = []
        if battery.isPresent {
            batteryItems = [
                ReportItem(key: "battery_health", label: "电池健康度",
                           value: battery.healthPercent.map { String(format: "%.1f%%", $0) },
                           state: battery.healthPercent == nil ? .unavailable : gradeState(battery.healthGrade),
                           note: battery.healthPercent == nil ? "本机未提供设计容量" : nil),
                item("battery_cycle_count", "循环次数", "\(battery.cycleCount)", battery.cycleCount > 0 ? .ok : .unavailable),
                item("battery_design_cycles", "设计循环上限", "\(battery.designCycleCount)", .ok),
                item("battery_design_capacity", "设计容量 (mAh)",
                     battery.designCapacity > 0 ? "\(battery.designCapacity)" : nil,
                     battery.designCapacity > 0 ? .ok : .unavailable),
                item("battery_full_capacity", "满充容量 (mAh)",
                     battery.healthCapacity > 0 ? "\(battery.healthCapacity)" : nil,
                     battery.healthCapacity > 0 ? .ok : .unavailable),
                item("battery_serial", "电池序列号", emptyToNil(battery.serialNumber), .ok),
                item("battery_gauge", "电池计量芯片", emptyToNil(battery.gaugeModel), .ok,
                     note: "Apple 不公开电芯制造商，此项为 BMS 芯片型号"),
                ReportItem(key: "battery_failure", label: "永久性故障",
                           value: battery.permanentFailure ? "yes" : "no",
                           state: battery.permanentFailure ? .critical : .ok, note: nil),
                item("battery_voltage", "电压 (V)",
                     battery.voltage > 0 ? String(format: "%.2f", battery.voltage) : nil,
                     battery.voltage > 0 ? .ok : .unavailable),
                item("battery_temperature", "温度 (°C)",
                     battery.temperature.map { String(format: "%.1f", $0) },
                     battery.temperature == nil ? .unavailable : .ok,
                     note: battery.temperature == nil ? "该机型未公开电池温度" : nil),
                ReportItem(key: "adapter_watts", label: "适配器功率 (W)",
                           value: battery.adapterWatts.map { "\($0)" },
                           state: battery.adapterWatts == nil ? .unavailable : .ok, note: nil)
            ]
            if battery.permanentFailure { issues += 1 }
            if let health = battery.healthPercent, health < 80 { issues += 1 }
        } else {
            batteryItems = [ReportItem(key: "battery", label: "电池", value: nil,
                                       state: .unavailable, note: "未检测到电池")]
        }
        sections.append(ReportSection(title: "电池 / Battery", items: batteryItems))

        // 外设
        sections.append(ReportSection(title: "外设 / Peripherals", items: peripheralsItems(info.peripherals)))

        // 一致性核验
        var consistencyItems: [ReportItem] = []
        for finding in ConsistencyAudit.run(info: info) {
            consistencyItems.append(ReportItem(
                key: finding.title,
                label: finding.title,
                value: finding.state == .unavailable ? nil : auditValue(finding.state),
                state: auditState(finding.state),
                note: finding.detail
            ))
            if finding.state == .inconsistent { risks += 1 }
            if finding.state == .notice { confirmations += 1 }
        }
        sections.append(ReportSection(title: "一致性核验 / Consistency", items: consistencyItems))

        // 原装性核对
        var originalityItems: [ReportItem] = []
        for finding in OriginalityCheck.run(info: info, battery: battery) {
            originalityItems.append(ReportItem(
                key: finding.title,
                label: finding.title,
                value: finding.state == .unavailable ? nil : auditValue(finding.state),
                state: auditState(finding.state),
                note: finding.source.map { "\(finding.detail) [\($0)]" } ?? finding.detail
            ))
            if finding.state == .inconsistent { risks += 1 }
            if finding.state == .notice { confirmations += 1 }
        }
        sections.append(ReportSection(title: "原装性核对 / Originality", items: originalityItems))

        // 结论必须与表格里的状态一致：出现过 warning 行就不能说「未发现问题」。
        // issues 是前面各段（序列号、崩溃日志、安全项、电池健康等）累计的计数，不能被覆盖。
        let totalIssues = issues + risks + confirmations
        let verdict: String
        if risks > 0 {
            verdict = T("发现 \(risks) 项不一致，另有 \(issues + confirmations) 项需确认，建议人工复核",
                        "\(risks) mismatch(es) plus \(issues + confirmations) item(s) to confirm — manual review advised")
        } else if totalIssues > 0 {
            verdict = T("未发现不一致，有 \(totalIssues) 项需人工确认",
                        "No mismatch found; \(totalIssues) item(s) need confirmation")
        } else {
            verdict = T("未发现需要关注的问题", "No issues found")
        }

        return (sections, verdict, totalIssues)
    }

    // MARK: - 输出

    static func markdown(info: MacSystemInfo, battery: BatterySnapshot) -> String {
        let report = build(info: info, battery: battery)
        var lines: [String] = []
        lines.append("# MacVerify 质检报告")
        lines.append("")
        lines.append("- 工具版本：\(BuildInfo.version) (\(BuildInfo.build))")
        lines.append("- 检测时间：\(Format.dateTime(info.scannedAt))")
        lines.append("- 报告指纹：\(DeviceFingerprint.display(fingerprint(of: report.sections)))")
        lines.append("- 结论：**\(report.verdict)**")
        lines.append("")
        lines.append("> 所有数值均为本机只读接口的实测结果。标为 `unavailable` 的项表示本机未向用户态提供该数据，")
        lines.append("> 不代表 0 或正常。")
        lines.append("")

        for section in report.sections {
            lines.append("## \(section.title)")
            lines.append("")
            lines.append("| 项目 | 数值 | 状态 | 说明 |")
            lines.append("| --- | --- | --- | --- |")
            for entry in section.items {
                let value = entry.value ?? "unavailable"
                lines.append("| \(entry.label) | \(value) | \(stateLabel(entry.state)) | \(entry.note ?? "") |")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func json(info: MacSystemInfo, battery: BatterySnapshot) -> Data? {
        let report = build(info: info, battery: battery)
        var root: [String: Any] = [
            "tool": "MacVerify",
            "version": BuildInfo.version,
            "build": BuildInfo.build,
            "fingerprint": fingerprint(of: report.sections),
            "scanned_at": ISO8601DateFormatter().string(from: info.scannedAt),
            "verdict": report.verdict,
            "issue_count": report.issues
        ]
        var sections: [String: Any] = [:]
        for section in report.sections {
            var items: [String: Any] = [:]
            for entry in section.items {
                var payload: [String: Any] = ["label": entry.label, "state": entry.state.rawValue]
                payload["value"] = entry.value ?? NSNull()
                if let note = entry.note { payload["note"] = note }
                items[entry.key] = payload
            }
            sections[section.title] = items
        }
        root["sections"] = sections
        return try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - 保存

    static func save(info: MacSystemInfo, battery: BatterySnapshot) {
        let panel = NSSavePanel()
        panel.title = T("保存质检报告", "Save inspection report")
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        }
        panel.nameFieldStringValue = "MacVerify-\(fileStamp(info.scannedAt)).md"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = markdown(info: info, battery: battery)
        try? text.write(to: url, atomically: true, encoding: .utf8)

        // 同时写出同名 JSON，便于机器读取
        if let data = json(info: info, battery: battery) {
            let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
            try? data.write(to: jsonURL)
        }
    }

    static func copyMarkdown(info: MacSystemInfo, battery: BatterySnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown(info: info, battery: battery), forType: .string)
    }

    // MARK: - 辅助

    private static func item(_ key: String, _ label: String, _ value: String?, _ state: ReportState,
                             note: String? = nil) -> ReportItem {
        let isEmpty = (value ?? "").isEmpty
        return ReportItem(key: key,
                          label: label,
                          value: isEmpty ? nil : value,
                          state: isEmpty ? .unavailable : state,
                          note: isEmpty && note == nil ? "该机型未提供此项数据" : note)
    }

    private static func tri(_ key: String, _ label: String, _ value: Bool?,
                            trueState: ReportState, falseState: ReportState,
                            trueNote: String? = nil, falseNote: String? = nil) -> ReportItem {
        guard let value = value else {
            return ReportItem(key: key, label: label, value: "unavailable",
                              state: .unavailable, note: "系统未返回该状态")
        }
        return ReportItem(key: key, label: label,
                          value: value ? "enabled" : "disabled",
                          state: value ? trueState : falseState,
                          note: value ? trueNote : falseNote)
    }

    private static func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "—" { return nil }
        return trimmed
    }

    // MARK: - 指纹

    /// 从已生成的报告行里取「硬件身份」字段算指纹。
    /// 直接读报告本身而不是重新采集，保证导出与校验用的是同一份数值。
    static func fingerprint(of sections: [ReportSection]) -> String {
        var values: [String: String] = [:]
        for section in sections {
            for entry in section.items where DeviceFingerprint.identityKeys.contains(entry.key) {
                values[entry.key] = entry.value ?? "unavailable"
            }
        }
        return DeviceFingerprint.compute(values)
    }

    // MARK: - 外设
    private static func peripheralsItems(_ p: PeripheralsInfo) -> [ReportItem] {
        var items: [ReportItem] = []

        var wifiItems: [ReportItem] = []
        if !p.wifi.scanAvailable {
            wifiItems.append(item("wifi", "Wi-Fi 硬件", nil, .unavailable))
        } else {
            wifiItems.append(item("wifi", "Wi-Fi 硬件",
                                  p.wifi.isPresent ? "present" : "absent",
                                  p.wifi.isPresent ? .ok : .warning))
        }
        if !p.wifi.bsdDevice.isEmpty {
            wifiItems.append(item("wifi_device", "Wi-Fi 接口", p.wifi.bsdDevice, .ok))
        }
        if !p.wifi.chipset.isEmpty {
            wifiItems.append(item("wifi_chipset", "Wi-Fi 芯片", p.wifi.chipset, .ok))
        }
        if !p.wifi.macSuffix.isEmpty {
            wifiItems.append(item("wifi_mac", "MAC 后四位", p.wifi.macSuffix, .ok,
                                  note: "完整 MAC 属于设备标识，不记录"))
        }
        items.append(contentsOf: wifiItems)

        items.append(item("bluetooth", "蓝牙硬件",
                          p.bluetooth.isPresent ? "present" : "absent",
                          p.bluetooth.isPresent ? .ok : .warning))
        if p.bluetooth.isPresent {
            items.append(item("bt_chipset", "蓝牙芯片", emptyToNil(p.bluetooth.chipset), .ok))
            items.append(item("bt_transport", "蓝牙总线", emptyToNil(p.bluetooth.transport), .ok))
            items.append(item("bt_firmware", "蓝牙固件", emptyToNil(p.bluetooth.firmwareVersion), .ok))
        }

        // 摄像头：只报系统枚举到的设备，不推断是否内建
        items.append(item("camera", "摄像头（系统枚举）",
                          p.camera.isPresent ? "\(p.camera.names.count)" : "0",
                          p.camera.isPresent ? .ok : .warning,
                          note: p.camera.names.isEmpty ? nil : p.camera.names.joined(separator: " / ")))

        if !p.audioScanAvailable {
            items.append(item("audio", "音频设备", nil, .unavailable))
        } else {
            if let mic = p.builtinMicrophone {
                items.append(item("mic", "内建麦克风", "\(mic.inputChannels) ch", .ok, note: mic.name))
            } else {
                items.append(item("mic", "内建麦克风", "absent", .warning))
            }
            if let speaker = p.builtinSpeaker {
                items.append(item("speaker", "内建扬声器", "\(speaker.outputChannels) ch", .ok, note: speaker.name))
            } else {
                items.append(item("speaker", "内建扬声器", "absent", .warning))
            }
            let external = p.audio.filter { !$0.isBuiltin }
            if !external.isEmpty {
                items.append(item("audio_other", "其他音频设备",
                                  "\(external.count)", .ok,
                                  note: external.map(\.name).joined(separator: " / ")))
            }
        }

        // USB：空数组是「没插设备」，不是读不到
        if !p.usbScanAvailable {
            items.append(item("usb", "USB 设备", nil, .unavailable))
            items.append(item("usb_list", "USB 设备清单", nil, .unavailable))
        } else if p.usbDevices.isEmpty {
            items.append(item("usb", "USB 设备", "0", .ok, note: "当前未连接 USB 设备"))
            items.append(item("usb_list", "USB 设备清单", "none", .ok))
        } else {
            let names = p.usbDevices.map(\.name).joined(separator: " / ")
            items.append(item("usb", "USB 设备", "\(p.usbDevices.count)", .ok,
                              note: p.usbDevices.map { device in
                                  device.speed.isEmpty ? device.name : "\(device.name) (\(device.speed))"
                              }.joined(separator: " / ")))
            items.append(item("usb_list", "USB 设备清单", names, .ok))
        }

        // 雷电：列出总线与各口状态
        if !p.thunderboltScanAvailable {
            items.append(item("thunderbolt", "雷雳总线", nil, .unavailable))
        } else if p.thunderboltBuses.isEmpty {
            items.append(item("thunderbolt", "雷雳总线", "0", .ok, note: "未检测到雷雳控制器"))
        } else {
            let ports = p.thunderboltBuses.reduce(0) { $0 + $1.receptacleStatus.count }
            let connected = p.thunderboltBuses.flatMap(\.receptacleStatus)
                .filter { $0 != "receptacle_no_devices_connected" }.count
            items.append(item("thunderbolt", "雷雳总线", "\(p.thunderboltBuses.count)", .ok,
                              note: p.thunderboltBuses.first?.speed))
            items.append(item("thunderbolt_ports", "雷雳口数", "\(ports)", .ok))
            items.append(item("thunderbolt_connected", "雷电口已连接设备", "\(connected)", .ok))
        }
        return items
    }

    private static func coresText(_ info: MacSystemInfo) -> String? {
        if info.performanceCores > 0, info.efficiencyCores > 0 {
            return "\(info.performanceCores)P + \(info.efficiencyCores)E / \(info.logicalCores) threads"
        }
        if info.physicalCores > 0 {
            return "\(info.physicalCores) cores / \(info.logicalCores) threads"
        }
        return nil
    }

    private static func gpuText(_ info: MacSystemInfo) -> String? {
        guard info.gpuName != "—" else { return nil }
        return info.gpuCores > 0 ? "\(info.gpuName) (\(info.gpuCores) cores)" : info.gpuName
    }

    private static func gradeState(_ grade: HealthGrade) -> ReportState {
        switch grade {
        case .excellent, .good: return .ok
        case .fair: return .warning
        case .service: return .critical
        case .unknown: return .unavailable
        }
    }

    private static func auditState(_ state: AuditState) -> ReportState {
        switch state {
        case .consistent: return .ok
        case .notice: return .warning
        case .inconsistent: return .critical
        case .unavailable: return .unavailable
        }
    }

    private static func auditValue(_ state: AuditState) -> String {
        switch state {
        case .consistent: return "consistent"
        case .notice: return "needs confirmation"
        case .inconsistent: return "mismatch"
        case .unavailable: return "unavailable"
        }
    }

    private static func stateLabel(_ state: ReportState) -> String {
        switch state {
        case .ok: return "ok"
        case .warning: return "warning"
        case .critical: return "critical"
        case .unavailable: return "unavailable"
        }
    }

    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
