// Views/Overview/OverviewChecksSection.swift
//
// 关键检查项。改造前是固定顺序的网格，异常项藏在中间；
// 现在按严重度排序：不一致 → 需确认 → 通过 → 不可用。
import SwiftUI

struct CheckItem {
    let title: String
    let value: String
    let level: BadgeLevel
    let target: SidebarItem?
}

struct OverviewChecksSection: View {
    let info: MacSystemInfo
    let battery: BatterySnapshot
    @Binding var selection: SidebarItem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm + 2) {
            SectionHeader(title: T("关键检查项", "KEY CHECKS"))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.md),
                                GridItem(.flexible(), spacing: Space.md)],
                      spacing: Space.md) {
                ForEach(Array(sortedItems.enumerated()), id: \.offset) { _, item in
                    row(item)
                }
            }
        }
    }

    private func row(_ item: CheckItem) -> some View {
        Button(action: {
            if let target = item.target { selection = target }
        }) {
            HStack(spacing: Space.sm) {
                Image(systemName: item.level.symbol)
                    .font(Typo.icon(13))
                    .foregroundColor(item.level.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(Typo.bodyStrong).foregroundColor(.primary)
                    Text(item.value).font(Typo.body).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if item.target != nil {
                    Image(systemName: "chevron.right")
                        .font(Typo.icon(10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Surface.fill))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Surface.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title)：\(item.value)")
        .accessibilityHint(item.target == nil ? "" : T("打开对应页面", "Opens the matching page"))
    }

    // MARK: - 数据

    private var sortedItems: [CheckItem] {
        items.sorted { rank($0.level) < rank($1.level) }
    }

    private func rank(_ level: BadgeLevel) -> Int {
        switch level {
        case .critical: return 0
        case .warning: return 1
        case .ok: return 2
        case .neutral: return 3
        }
    }

    private var items: [CheckItem] {
        var items: [CheckItem] = []

        if battery.isPresent {
            if let health = battery.healthPercent {
                items.append(CheckItem(
                    title: T("电池健康度", "Battery health"),
                    value: "\(String(format: "%.1f", health))% · \(battery.cycleCount) \(T("次循环", "cycles"))",
                    level: batteryCheckLevel,
                    target: .battery
                ))
            } else {
                items.append(CheckItem(
                    title: T("电池健康度", "Battery health"),
                    value: T("数据不可用", "Unavailable"),
                    level: .neutral,
                    target: .battery
                ))
            }
        } else {
            items.append(CheckItem(
                title: T("电池", "Battery"),
                value: T("未检测到电池", "No battery detected"),
                level: .neutral,
                target: .battery
            ))
        }

        items.append(CheckItem(
            title: T("激活锁", "Activation Lock"),
            value: statusText(info.activationLock, on: T("已开启", "Enabled"), off: T("已关闭", "Disabled")),
            level: info.activationLock == true ? .warning : (info.activationLock == false ? .ok : .neutral),
            target: .security
        ))

        items.append(CheckItem(
            title: T("文件保险箱", "FileVault"),
            value: statusText(info.fileVault, on: T("已加密", "Encrypted"), off: T("未加密", "Not encrypted")),
            level: info.fileVault == true ? .ok : .neutral,
            target: .security
        ))

        items.append(CheckItem(
            title: T("MDM 描述文件", "MDM enrollment"),
            value: statusText(info.mdmEnrolled, on: T("已注册", "Enrolled"), off: T("未注册", "Not enrolled")),
            level: info.mdmEnrolled == true ? .warning : (info.mdmEnrolled == false ? .ok : .neutral),
            target: .security
        ))

        if let smart = info.storage.smartHealthPercent {
            items.append(CheckItem(
                title: T("SSD 健康度", "SSD health"),
                value: "\(smart)% · \(info.storage.deviceName)",
                level: smart >= 80 ? .ok : (smart >= 50 ? .warning : .critical),
                target: .storage
            ))
        } else {
            items.append(CheckItem(
                title: T("SSD 健康度", "SSD health"),
                value: T("未返回 SMART 数据", "No SMART data"),
                level: .neutral,
                target: .storage
            ))
        }

        items.append(CheckItem(
            title: T("系统崩溃记录", "Kernel panics"),
            value: panicSummary,
            level: !info.panicScanAvailable ? .neutral : (info.panicLogCount > 0 ? .warning : .ok),
            target: .security
        ))

        items.append(CheckItem(
            title: T("显示屏", "Display"),
            value: "\(info.display.inchText) · \(info.display.resolutionText)",
            level: .neutral,
            target: .display
        ))

        return items
    }

    private func statusText(_ value: Bool?, on: String, off: String) -> String {
        guard let value = value else { return T("无法读取", "Unavailable") }
        return value ? on : off
    }

    private var panicSummary: String {
        guard info.panicScanAvailable else { return T("无法读取", "Unavailable") }
        return info.panicLogCount > 0
            ? T("\(info.panicLogCount) 条记录", "\(info.panicLogCount) records")
            : T("无记录", "None")
    }

    private var batteryCheckLevel: BadgeLevel {
        switch battery.healthGrade {
        case .excellent, .good: return .ok
        case .fair: return .warning
        case .service: return .critical
        case .unknown: return .neutral
        }
    }
}
