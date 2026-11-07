// Services/OriginalityCheck.swift
//
// 原装性核对：把本机实测的屏幕、内存、存储、电池规格，与该机型的 Apple 官方规格基线比对。
//
// 与 ConsistencyAudit 的分工：
//   ConsistencyAudit —— 两条本机通路互相印证（不依赖外部数据）
//   OriginalityCheck —— 本机实测值对照 Apple 官方规格（依赖 ModelSpecCatalog）
//
// 措辞约束：不匹配只能说明「与官方规格不符」，不能直接断言「非原装」——
// 换过整块主板、机器经过 Apple 维修、或基线表本身有误都会产生同样的现象。
import Foundation

struct OriginalityFinding: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let state: AuditState
    /// 数据来源，界面上不强展示，但报告里要留痕
    let source: String?
}

enum OriginalityCheck {

    /// 电池包标称电压。Apple 这几代 3-cell 电池组均在 11.4–11.5V，
    /// 用 11.45V 把 mAh 折算成 Wh 与官方额定值比对（14 吋 2023：6075mAh×11.45 ≈ 69.6Wh，与官方 69.6Wh 相符）。
    /// 该折算只用于「是否相差过大」的粗判，结论措辞为「建议确认」。
    private static let nominalPackVoltage = 11.45
    private static let batteryTolerance = 0.10
    private static let storageTolerance = 0.03
    private static let displayToleranceInches = 0.6

    static func run(info: MacSystemInfo, battery: BatterySnapshot) -> [OriginalityFinding] {
        guard let spec = ModelSpecCatalog.spec(for: info.modelIdentifier) else {
            return [OriginalityFinding(
                title: T("原装性核对", "Originality check"),
                detail: T("该机型暂未收录官方规格基线，不做原装性判断。",
                          "No spec baseline is available for this model, so no originality judgement is made."),
                state: .unavailable,
                source: nil
            )]
        }

        var findings: [OriginalityFinding] = []
        findings.append(displayCheck(info.display, spec))
        findings.append(memoryCheck(info, spec))
        findings.append(storageCheck(info.storage, spec))
        findings.append(gpuCheck(info, spec))
        if battery.isPresent {
            findings.append(batteryCapacityCheck(battery, spec))
            findings.append(batteryDataCheck(battery))
        }
        return findings
    }

    // MARK: - 屏幕

    private static func displayCheck(_ display: DisplayInfo, _ spec: ModelSpec) -> OriginalityFinding {
        let title = T("内建屏规格", "Built-in display spec")
        guard display.isBuiltin, display.pixelWidth > 0, display.pixelHeight > 0 else {
            return OriginalityFinding(
                title: title,
                detail: T("未检测到内建屏，跳过该项。", "No built-in display detected; skipped."),
                state: .unavailable,
                source: spec.source
            )
        }

        let expected = "\(spec.nativeWidth)×\(spec.nativeHeight)"
        let actual = "\(display.pixelWidth)×\(display.pixelHeight)"
        let resolutionOK = display.pixelWidth == spec.nativeWidth && display.pixelHeight == spec.nativeHeight

        guard resolutionOK else {
            return OriginalityFinding(
                title: title,
                detail: T("官方原生分辨率为 \(expected)，实测为 \(actual)。分辨率不一致说明面板或机型标识与该机型不符，请人工确认。",
                          "Apple specifies \(expected) native; this Mac reports \(actual). The panel or the model identifier does not match this model — verify manually."),
                state: .inconsistent,
                source: spec.source
            )
        }

        if display.inches > 0, abs(display.inches - spec.displayInches) > displayToleranceInches {
            return OriginalityFinding(
                title: title,
                detail: T("分辨率 \(actual) 与官方一致，但实测对角线 \(String(format: "%.1f", display.inches))″ 与官方 \(String(format: "%.1f", spec.displayInches))″ 相差较大。",
                          "Resolution \(actual) matches Apple's spec, but the measured diagonal \(String(format: "%.1f", display.inches))″ differs from Apple's \(String(format: "%.1f", spec.displayInches))″."),
                state: .notice,
                source: spec.source
            )
        }

        return OriginalityFinding(
            title: title,
            detail: T("分辨率 \(actual)、对角线 \(String(format: "%.1f", display.inches))″ 与官方规格一致。",
                      "Resolution \(actual) and the \(String(format: "%.1f", display.inches))″ diagonal match Apple's spec."),
            state: .consistent,
            source: spec.source
        )
    }

    // MARK: - 内存

    private static func memoryCheck(_ info: MacSystemInfo, _ spec: ModelSpec) -> OriginalityFinding {
        let title = T("内存档位", "Memory configuration")
        guard info.memoryGB > 0 else {
            return OriginalityFinding(
                title: title,
                detail: T("未能读取内存容量。", "Memory size unavailable."),
                state: .unavailable,
                source: spec.source
            )
        }
        let options = spec.memoryOptionsGB.map { "\($0)" }.joined(separator: " / ")
        if spec.memoryOptionsGB.contains(info.memoryGB) {
            return OriginalityFinding(
                title: title,
                detail: T("\(info.memoryGB) GB 属于官方可选档位（\(options) GB）。",
                          "\(info.memoryGB) GB is one of Apple's options (\(options) GB)."),
                state: .consistent,
                source: spec.source
            )
        }
        return OriginalityFinding(
            title: title,
            detail: T("实测 \(info.memoryGB) GB，不在官方可选档位（\(options) GB）之内。内存为板载不可更换，出现这种情况通常意味着机型标识与实物不符，请人工确认。",
                      "Measured \(info.memoryGB) GB, which is not one of Apple's options (\(options) GB). Memory is soldered, so this usually means the model identifier does not match the hardware — verify manually."),
            state: .inconsistent,
            source: spec.source
        )
    }

    // MARK: - 存储

    private static func storageCheck(_ storage: StorageInfo, _ spec: ModelSpec) -> OriginalityFinding {
        let title = T("存储档位", "Storage configuration")
        // 该机型硬盘可自行更换，容量不符属于正常，不做判断
        guard spec.storageSoldered else {
            return OriginalityFinding(
                title: title,
                detail: T("该机型硬盘可自行更换，容量与出厂配置不同属正常，不做判断。",
                          "This model has a user-replaceable drive, so a different capacity is normal; not judged."),
                state: .unavailable,
                source: spec.source
            )
        }
        // 从外接盘启动时，读到的容量属于外接盘，与内置 SSD 无关
        if storage.isInternalDisk == false {
            return OriginalityFinding(
                title: title,
                detail: T("当前从外接磁盘启动，读到的容量不代表内置 SSD，跳过该项。",
                          "Booting from an external disk, so the measured capacity is not the internal SSD; skipped."),
                state: .unavailable,
                source: spec.source
            )
        }
        guard storage.physicalBytes > 0 else {
            return OriginalityFinding(
                title: title,
                detail: T("未能读取物理容量。", "Physical capacity unavailable."),
                state: .unavailable,
                source: spec.source
            )
        }
        let measuredGB = Double(storage.physicalBytes) / 1_000_000_000
        let matched = spec.storageOptionsGB.first { option in
            abs(measuredGB - Double(option)) / Double(option) <= storageTolerance
        }
        let options = spec.storageOptionsGB.map(storageLabel).joined(separator: " / ")

        if let matched = matched {
            return OriginalityFinding(
                title: title,
                detail: T("物理容量 \(String(format: "%.0f", measuredGB)) GB，对应官方 \(storageLabel(matched)) 档位。",
                          "Physical capacity \(String(format: "%.0f", measuredGB)) GB, matching Apple's \(storageLabel(matched)) option."),
                state: .consistent,
                source: spec.source
            )
        }
        return OriginalityFinding(
            title: title,
            detail: T("物理容量 \(String(format: "%.0f", measuredGB)) GB，不匹配官方档位（\(options)）。可能更换过硬盘，或机型标识与实物不符。",
                      "Physical capacity \(String(format: "%.0f", measuredGB)) GB does not match Apple's options (\(options)). The drive may have been replaced, or the model identifier does not match the hardware."),
            state: .notice,
            source: spec.source
        )
    }

    /// 把十进制容量映射回 Apple 的营销名称（500 → 512GB，1000 → 1TB）
    private static func storageLabel(_ decimalGB: Int) -> String {
        switch decimalGB {
        case 121: return "128GB"
        case 251: return "256GB"
        case 500: return "512GB"
        case 1000: return "1TB"
        case 2000: return "2TB"
        case 4000: return "4TB"
        case 8000: return "8TB"
        default: return "\(decimalGB)GB"
        }
    }

    // MARK: - GPU
    private static func gpuCheck(_ info: MacSystemInfo, _ spec: ModelSpec) -> OriginalityFinding {
        let title = T("GPU 核心数", "GPU core count")
        // Intel 机型为独立显卡，核心数不由机型唯一决定，该项不适用
        guard !spec.gpuCores.isEmpty else {
            return OriginalityFinding(
                title: title,
                detail: T("该机型为独立显卡，GPU 核心数不由机型决定，不做判断。",
                          "This model uses a discrete GPU, so the core count does not identify the model; not judged."),
                state: .unavailable,
                source: spec.source
            )
        }
        guard info.gpuCores > 0 else {
            return OriginalityFinding(
                title: title,
                detail: T("未能读取 GPU 核心数。", "GPU core count unavailable."),
                state: .unavailable,
                source: spec.source
            )
        }
        let options = spec.gpuCores.map { "\($0)" }.joined(separator: " / ")
        if spec.gpuCores.contains(info.gpuCores) {
            return OriginalityFinding(
                title: title,
                detail: T("\(info.gpuCores) 核，属于官方可选（\(options) 核）。",
                          "\(info.gpuCores) cores, one of Apple's options (\(options))."),
                state: .consistent,
                source: spec.source
            )
        }
        return OriginalityFinding(
            title: title,
            detail: T("\(info.gpuCores) 核，不在官方可选范围（\(options) 核）内。",
                      "\(info.gpuCores) cores is not among Apple's options (\(options))."),
            state: .inconsistent,
            source: spec.source
        )
    }

    // MARK: - 电池

    private static func batteryCapacityCheck(_ battery: BatterySnapshot, _ spec: ModelSpec) -> OriginalityFinding {
        let title = T("电池容量规格", "Battery capacity spec")
        guard battery.designCapacity > 0 else {
            return OriginalityFinding(
                title: title,
                detail: T("该机型未提供设计容量，无法核对。", "Design capacity is not exposed on this Mac."),
                state: .unavailable,
                source: spec.source
            )
        }
        let wh = Double(battery.designCapacity) * nominalPackVoltage / 1000
        let deviation = (wh - spec.batteryActualWh) / spec.batteryActualWh

        if abs(deviation) <= batteryTolerance {
            return OriginalityFinding(
                title: title,
                detail: T("设计容量 \(battery.designCapacity) mAh ≈ \(String(format: "%.1f", wh)) Wh，与官方额定 \(String(format: "%.1f", spec.batteryActualWh)) Wh 相符。",
                          "Design capacity \(battery.designCapacity) mAh ≈ \(String(format: "%.1f", wh)) Wh, consistent with Apple's rated \(String(format: "%.1f", spec.batteryActualWh)) Wh."),
                state: .consistent,
                source: spec.source
            )
        }
        return OriginalityFinding(
            title: title,
            detail: T("设计容量 \(battery.designCapacity) mAh ≈ \(String(format: "%.1f", wh)) Wh，与官方额定 \(String(format: "%.1f", spec.batteryActualWh)) Wh 相差 \(String(format: "%+.0f", deviation * 100))%。该电池可能不是该机型的原装规格，建议确认更换记录。",
                      "Design capacity \(battery.designCapacity) mAh ≈ \(String(format: "%.1f", wh)) Wh, \(String(format: "%+.0f", deviation * 100))% off Apple's rated \(String(format: "%.1f", spec.batteryActualWh)) Wh. This battery may not be the original spec for this model — check the service history."),
            state: .notice,
            source: spec.source
        )
    }

    /// 纯逻辑自洽：满充容量不应显著大于设计容量。
    /// 注意留 5% 容差——全新电芯的实际容量略高于标称值是正常现象（Apple 的「最大容量」也可能显示 101%），
    /// 只有明显超出才说明设计容量被改写。
    private static func batteryDataCheck(_ battery: BatterySnapshot) -> OriginalityFinding {
        let title = T("电池数据自洽", "Battery data sanity")
        guard battery.designCapacity > 0, battery.rawMaxCapacity > 0 else {
            return OriginalityFinding(
                title: title,
                detail: T("容量数据不完整，无法核对。", "Capacity data incomplete."),
                state: .unavailable,
                source: nil
            )
        }
        let ceiling = Double(battery.designCapacity) * 1.05
        if Double(battery.rawMaxCapacity) <= ceiling {
            return OriginalityFinding(
                title: title,
                detail: T("满充容量 \(battery.rawMaxCapacity) mAh / 设计容量 \(battery.designCapacity) mAh，比例正常。",
                          "Full charge \(battery.rawMaxCapacity) mAh vs design \(battery.designCapacity) mAh — normal ratio."),
                state: .consistent,
                source: nil
            )
        }
        return OriginalityFinding(
            title: title,
            detail: T("满充容量 \(battery.rawMaxCapacity) mAh 比设计容量 \(battery.designCapacity) mAh 高出 \(String(format: "%.0f", (Double(battery.rawMaxCapacity) / Double(battery.designCapacity) - 1) * 100))%，超出电芯正常波动范围。设计容量很可能被改写以虚报健康度。",
                      "Full charge capacity \(battery.rawMaxCapacity) mAh exceeds design capacity \(battery.designCapacity) mAh by \(String(format: "%.0f", (Double(battery.rawMaxCapacity) / Double(battery.designCapacity) - 1) * 100))%, beyond normal cell variation. The design capacity has likely been rewritten to inflate the health figure."),
            state: .inconsistent,
            source: nil
        )
    }
}
