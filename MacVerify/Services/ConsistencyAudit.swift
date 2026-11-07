// Services/ConsistencyAudit.swift
//
// 一致性核验：判断"这台机器报出来的身份"与"这台机器真实的样子"是否自洽。
//
// 设计原则：只使用两条独立数据通路互相印证，不引入外部规格库。
// 理由：任何"该机型应该是什么配置"的外部对照表都会过期，写错就是新的假数据；
// 而"系统报告说 A、内核接口说 B"这种不一致，本身就是改机型/刷序列号的直接证据。
import Foundation

enum AuditState {
    case consistent
    case notice
    case inconsistent
    case unavailable

    var symbol: String {
        switch self {
        case .consistent: return "checkmark.circle.fill"
        case .notice: return "info.circle.fill"
        case .inconsistent: return "exclamationmark.triangle.fill"
        case .unavailable: return "minus.circle"
        }
    }
}

struct AuditFinding: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let state: AuditState
}

enum ConsistencyAudit {

    static func run(info: MacSystemInfo) -> [AuditFinding] {
        var findings: [AuditFinding] = []
        findings.append(modelIdentifierCheck(info))
        findings.append(serialCheck(info))
        findings.append(chipCheck(info))
        findings.append(storageSizeCheck(info))
        findings.append(storageNameCheck(info))
        findings.append(displayCheck(info))
        findings.append(memoryCheck(info))
        return findings
    }

    static func hasIssue(_ info: MacSystemInfo) -> Bool {
        run(info: info).contains { $0.state == .inconsistent }
    }

    // MARK: - 逐项

    /// system_profiler 的 machine_model 与 sysctl hw.model 必须一致
    private static func modelIdentifierCheck(_ info: MacSystemInfo) -> AuditFinding {
        guard let fromSysctl = info.modelFromSysctl, !fromSysctl.isEmpty else {
            return AuditFinding(
                title: T("机型标识双源核对", "Model identifier cross-check"),
                detail: T("未能从内核接口读取 hw.model，无法交叉核对。",
                          "Could not read hw.model from the kernel interface."),
                state: .unavailable
            )
        }
        let fromProfile = info.modelIdentifier
        if fromProfile == fromSysctl {
            return AuditFinding(
                title: T("机型标识双源核对", "Model identifier cross-check"),
                detail: T("系统报告与内核接口一致：\(fromProfile)",
                          "System report and kernel agree: \(fromProfile)"),
                state: .consistent
            )
        }
        return AuditFinding(
            title: T("机型标识双源核对", "Model identifier cross-check"),
            detail: T("系统报告为 \(fromProfile)，内核接口为 \(fromSysctl)，两者不一致。这不正常，建议重新安装系统后再核验。",
                      "System report says \(fromProfile) but the kernel says \(fromSysctl). This should not happen — reinstall macOS and re-check."),
            state: .inconsistent
        )
    }

    /// 序列号：系统报告 vs IOKit IOPlatformExpertDevice
    private static func serialCheck(_ info: MacSystemInfo) -> AuditFinding {
        guard let iokit = info.serialFromIOKit, !iokit.isEmpty,
              let reported = Optional(info.serialNumber), reported != "—" else {
            return AuditFinding(
                title: T("序列号双源核对", "Serial cross-check"),
                detail: T("未能同时读取两个来源的序列号。",
                          "Could not read the serial from both sources."),
                state: .unavailable
            )
        }
        if iokit == reported {
            return AuditFinding(
                title: T("序列号双源核对", "Serial cross-check"),
                detail: T("IOKit 与系统报告一致。", "IOKit and the system report agree."),
                state: .consistent
            )
        }
        return AuditFinding(
            title: T("序列号双源核对", "Serial cross-check"),
            detail: T("IOKit 读到 \(iokit)，系统报告为 \(reported)，两者不一致。",
                      "IOKit returned \(iokit) but the system report says \(reported)."),
            state: .inconsistent
        )
    }

    /// 芯片：系统报告 chip_type vs sysctl machdep.cpu.brand_string
    private static func chipCheck(_ info: MacSystemInfo) -> AuditFinding {
        guard let fromSysctl = info.chipFromSysctl, !fromSysctl.isEmpty else {
            return AuditFinding(
                title: T("芯片双源核对", "Chip cross-check"),
                detail: T("内核接口未提供 cpu.brand_string。", "The kernel did not expose cpu.brand_string."),
                state: .unavailable
            )
        }
        if info.chipName == fromSysctl {
            return AuditFinding(
                title: T("芯片双源核对", "Chip cross-check"),
                detail: T("两个来源一致：\(fromSysctl)", "Both sources agree: \(fromSysctl)"),
                state: .consistent
            )
        }
        return AuditFinding(
            title: T("芯片双源核对", "Chip cross-check"),
            detail: T("系统报告为 \(info.chipName)，内核接口为 \(fromSysctl)。",
                      "System report says \(info.chipName) but the kernel says \(fromSysctl)."),
            state: .inconsistent
        )
    }

    /// 物理盘容量：diskutil vs IOMedia
    private static func storageSizeCheck(_ info: MacSystemInfo) -> AuditFinding {
        let storage = info.storage
        guard storage.diskSizeFromDiskutil > 0, storage.diskSizeFromIOMedia > 0 else {
            return AuditFinding(
                title: T("磁盘容量双源核对", "Disk size cross-check"),
                detail: T("未同时取得 diskutil 与 IOMedia 的容量。",
                          "Both diskutil and IOMedia sizes were not available."),
                state: .unavailable
            )
        }
        let diff = abs(Double(storage.diskSizeFromDiskutil) - Double(storage.diskSizeFromIOMedia))
        let ratio = diff / Double(max(storage.diskSizeFromDiskutil, 1))
        if ratio < 0.001 {
            return AuditFinding(
                title: T("磁盘容量双源核对", "Disk size cross-check"),
                detail: T("diskutil 与 IOMedia 一致。", "diskutil and IOMedia agree."),
                state: .consistent
            )
        }
        return AuditFinding(
            title: T("磁盘容量双源核对", "Disk size cross-check"),
            detail: T("diskutil 报告 \(storage.diskSizeFromDiskutil) 字节，IOMedia 报告 \(storage.diskSizeFromIOMedia) 字节，差异超过 0.1%。",
                      "diskutil reports \(storage.diskSizeFromDiskutil) bytes, IOMedia reports \(storage.diskSizeFromIOMedia) bytes — more than 0.1% apart."),
            state: .inconsistent
        )
    }

    /// Apple 原厂 SSD 的介质名以 "APPLE SSD" 开头；更换过的硬盘不会是这个名字。
    private static func storageNameCheck(_ info: MacSystemInfo) -> AuditFinding {
        let name = info.storage.deviceName
        guard name != "—", !name.isEmpty else {
            return AuditFinding(
                title: T("硬盘是否为原厂介质", "Original drive check"),
                detail: T("未能读取介质名称。", "Media name unavailable."),
                state: .unavailable
            )
        }
        if name.uppercased().hasPrefix("APPLE SSD") {
            return AuditFinding(
                title: T("硬盘是否为原厂介质", "Original drive check"),
                detail: T("介质名为 \(name)，符合 Apple 原厂 SSD 命名。",
                          "Media name is \(name), consistent with an Apple-supplied SSD."),
                state: .consistent
            )
        }
        return AuditFinding(
            title: T("硬盘是否为原厂介质", "Original drive check"),
            detail: T("介质名为 \(name)，不是 Apple 原厂 SSD 的命名。Intel 机型可正常更换硬盘；Apple Silicon 机型的硬盘为板载，出现其它名称需确认是否外接启动盘。",
                      "Media name is \(name), which is not an Apple SSD. Intel Macs allow drive replacement; Apple Silicon drives are soldered, so another name suggests booting from an external disk."),
            state: .notice
        )
    }

    /// 内建屏存在时，CGDisplay 与系统报告应给出同一个产品 ID
    private static func displayCheck(_ info: MacSystemInfo) -> AuditFinding {
        let display = info.display
        guard display.isBuiltin else {
            return AuditFinding(
                title: T("内建屏身份核对", "Built-in display check"),
                detail: T("当前主屏不是内建屏，无法核对。", "The main display is not built-in."),
                state: .unavailable
            )
        }
        guard let panel = display.panel else {
            return AuditFinding(
                title: T("内建屏身份核对", "Built-in display check"),
                detail: T("本机未提供面板身份信息。", "Panel identity is not exposed on this Mac."),
                state: .unavailable
            )
        }
        if panel.productID > 0, display.modelID > 0, panel.productID == display.modelID {
            return AuditFinding(
                title: T("内建屏身份核对", "Built-in display check"),
                detail: T("面板型号 \(panel.productText) 与 CoreGraphics 报告一致。",
                          "Panel product \(panel.productText) matches CoreGraphics."),
                state: .consistent
            )
        }
        return AuditFinding(
            title: T("内建屏身份核对", "Built-in display check"),
            detail: T("系统报告的面板型号为 \(panel.productText)，CoreGraphics 报告为 \(String(format: "0x%04X", display.modelID))。",
                      "System report panel product is \(panel.productText); CoreGraphics reports \(String(format: "0x%04X", display.modelID))."),
            state: .inconsistent
        )
    }

    /// 内存：hw.memsize 与界面显示值应能对上
    private static func memoryCheck(_ info: MacSystemInfo) -> AuditFinding {
        guard info.memoryBytesFromSysctl > 0 else {
            return AuditFinding(
                title: T("内存容量自检", "Memory size check"),
                detail: T("内核接口未提供 hw.memsize。", "The kernel did not expose hw.memsize."),
                state: .unavailable
            )
        }
        let bytes = info.memoryBytesFromSysctl
        let gib = Double(bytes) / 1_073_741_824
        let isStandard = abs(gib - gib.rounded()) < 0.01 && [8.0, 16.0, 18.0, 24.0, 32.0, 36.0, 48.0, 64.0, 96.0, 128.0, 192.0].contains(gib.rounded())
        if isStandard {
            return AuditFinding(
                title: T("内存容量自检", "Memory size check"),
                detail: T("\(Int(gib.rounded())) GB，属于常见配置。", "\(Int(gib.rounded())) GB, a standard configuration."),
                state: .consistent
            )
        }
        return AuditFinding(
            title: T("内存容量自检", "Memory size check"),
            detail: T("\(String(format: "%.2f", gib)) GB，不是常见内存配置，建议人工确认。",
                      "\(String(format: "%.2f", gib)) GB is not a standard configuration — verify manually."),
            state: .notice
        )
    }
}
