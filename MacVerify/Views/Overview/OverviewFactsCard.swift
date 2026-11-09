// Views/Overview/OverviewFactsCard.swift
//
// 概览页左侧事实表：图标 + 标签 + 右对齐值，一行一条。
// 值取不到时显示「不可用」，不用 0、空串或估算值填空。
import SwiftUI

/// 带图标的一条事实。与 Components.Fact 的区别只是多一个前置图标。
struct IconFact {
    let icon: String
    let label: String
    let value: String
    var mono: Bool = false
    var state: ValueState = .normal
}

struct OverviewFactsCard: View {
    let info: MacSystemInfo

    private var unavailableText: String { T("不可用", "Unavailable") }

    var body: some View {
        Card(title: T("设备信息", "Device"), icon: "laptopcomputer") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    row(fact)
                }

                Text(footnote)
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.sm)
            }
        }
    }

    // MARK: - 行

    private func row(_ fact: IconFact) -> some View {
        HStack(spacing: Space.md) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: fact.icon)
                        .font(Typo.icon(9, weight: .semibold))
                        .foregroundColor(.accentColor)
                )

            Text(fact.label)
                .font(Typo.body)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: Space.md)

            valueView(fact)
        }
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(fact.label)：\(fact.value)")
    }

    @ViewBuilder
    private func valueView(_ fact: IconFact) -> some View {
        if fact.state == .normal {
            Text(fact.value)
                .font(fact.mono ? Typo.mono : Typo.value)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(fact.value)
        } else {
            HStack(spacing: 3) {
                Image(systemName: fact.state == .unavailable ? "minus.circle" : "slash.circle")
                    .font(Typo.icon(9))
                Text(fact.value).font(Typo.body)
            }
            .foregroundColor(StatusPalette.neutral)
            .lineLimit(1)
        }
    }

    // MARK: - 数据

    private var facts: [IconFact] {
        let modelNumber = info.modelNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        return [
            IconFact(icon: "laptopcomputer",
                     label: T("设备型号", "Model"),
                     value: info.modelDisplayName),

            IconFact(icon: "number",
                     label: T("机壳型号", "Model no."),
                     value: modelNumber.isEmpty ? unavailableText : modelNumber,
                     mono: true,
                     state: modelNumber.isEmpty ? .unavailable : .normal),

            regionFact,

            IconFact(icon: "cpu",
                     label: T("芯片平台", "Chip"),
                     value: info.chipName),

            IconFact(icon: "number.square",
                     label: T("设备序列号", "Serial"),
                     value: info.serialNumber,
                     mono: true),

            memoryFact,
            storageFact,

            byteFact(icon: "arrow.down.circle",
                     label: T("SSD 累计读取", "SSD read"),
                     value: storageReadBytes),

            byteFact(icon: "arrow.up.circle",
                     label: T("SSD 累计写入", "SSD write"),
                     value: storageWrittenBytes),

            IconFact(icon: "display",
                     label: T("显示尺寸", "Display"),
                     value: info.display.inches > 0 ? info.display.inchText : unavailableText,
                     state: info.display.inches > 0 ? .normal : .unavailable),

            IconFact(icon: "rectangle.on.rectangle",
                     label: T("分辨率", "Resolution"),
                     value: info.display.pixelWidth > 0 && info.display.pixelHeight > 0
                         ? info.display.resolutionText : unavailableText,
                     state: info.display.pixelWidth > 0 && info.display.pixelHeight > 0 ? .normal : .unavailable),

            IconFact(icon: "clock",
                     label: T("上次扫描", "Scanned"),
                     value: Format.dateTime(info.scannedAt))
        ]
    }

    /// 销售区域由配置编号后缀决定（Z17G000NALL/A → LL → 美版）。
    /// 编号读不到、或后缀不在已确认的对照表里，都写「未知」，不按机型或年份推测。
    private var regionFact: IconFact {
        let label = T("区域", "Region")

        if let region = RegionCatalog.region(forPartNumber: info.partNumber) {
            return IconFact(icon: "globe", label: label,
                            value: T("\(region.name)（\(region.code)/A）",
                                     "\(region.name) (\(region.code)/A)"))
        }
        if let suffix = RegionCatalog.unknownSuffix(forPartNumber: info.partNumber) {
            return IconFact(icon: "globe", label: label,
                            value: T("未知（后缀 \(suffix)）", "Unknown (suffix \(suffix))"),
                            state: .unavailable)
        }
        return IconFact(icon: "globe", label: label,
                        value: T("配置编号不可用", "Part number unavailable"),
                        state: .unavailable)
    }

    private var memoryFact: IconFact {
        guard info.memoryGB > 0 else {
            return IconFact(icon: "memorychip", label: T("内存", "Memory"),
                            value: unavailableText, state: .unavailable)
        }
        let suffix = info.isAppleSilicon ? T(" 统一内存", " unified") : ""
        return IconFact(icon: "memorychip", label: T("内存", "Memory"),
                        value: "\(info.memoryGB) GB\(suffix)")
    }

    private var storageFact: IconFact {
        // 从外接盘启动时，容量与型号都不代表机身内置 SSD，标签也要跟着改。
        let isExternal = info.storage.isInternalDisk == false
        let label = isExternal ? T("启动磁盘", "Boot disk") : T("内部存储", "Storage")

        var parts: [String] = []
        if info.storage.marketingCapacity != "—" { parts.append(info.storage.marketingCapacity) }
        if !info.storage.deviceName.isEmpty, info.storage.deviceName != "—" {
            parts.append(info.storage.deviceName)
        }
        if isExternal { parts.append(T("外接", "external")) }

        guard !parts.isEmpty else {
            return IconFact(icon: "internaldrive", label: label, value: unavailableText, state: .unavailable)
        }
        return IconFact(icon: "internaldrive", label: label, value: parts.joined(separator: " · "))
    }

    private func byteFact(icon: String, label: String, value: UInt64?) -> IconFact {
        guard let value = value else {
            return IconFact(icon: icon, label: label, value: unavailableText, state: .unavailable)
        }
        return IconFact(icon: icon, label: label, value: Format.bytes(value))
    }

    /// 优先 NVMe 全生命周期计数；没有 SMART 时退回卷级统计（格式化清零），两者不能混为一谈。
    private var storageReadBytes: UInt64? {
        if let lifetime = info.storage.smartLifetimeReadBytes { return lifetime }
        return info.storage.statisticsAvailable ? info.storage.readBytes : nil
    }

    private var storageWrittenBytes: UInt64? {
        if let lifetime = info.storage.smartLifetimeWrittenBytes { return lifetime }
        return info.storage.statisticsAvailable ? info.storage.writtenBytes : nil
    }

    private var footnote: String {
        T("读写量优先取 NVMe 全生命周期计数；没有 SMART 时退回卷级统计，格式化后会清零。",
          "Read/write totals prefer the NVMe lifetime counters; without SMART they fall back to volume statistics, which reset on erase.")
    }
}
