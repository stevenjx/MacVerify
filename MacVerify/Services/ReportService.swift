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
                       note: storage.smartHealthPercent == nil ? "本机未向用户态公开 SMART 数据" : nil)
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
            if finding.state == .inconsistent { issues += 1 }
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
            if finding.state == .inconsistent { issues += 1 }
        }
        sections.append(ReportSection(title: "原装性核对 / Originality", items: originalityItems))

        let verdict: String
        if issues == 0 {
            verdict = T("未发现需要关注的问题", "No issues found")
        } else if issues <= 2 {
            verdict = T("发现 \(issues) 项需要确认", "\(issues) item(s) need confirmation")
        } else {
            verdict = T("发现 \(issues) 项风险，建议人工复核", "\(issues) risk(s) found — manual review advised")
        }

        return (sections, verdict, issues)
    }

    // MARK: - 输出

    static func markdown(info: MacSystemInfo, battery: BatterySnapshot) -> String {
        let report = build(info: info, battery: battery)
        var lines: [String] = []
        lines.append("# MacVerify 质检报告")
        lines.append("")
        lines.append("- 工具版本：\(BuildInfo.version) (\(BuildInfo.build))")
        lines.append("- 检测时间：\(Format.dateTime(info.scannedAt))")
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
