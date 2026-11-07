// Views/OverviewView.swift
import SwiftUI

struct CheckItem {
    let title: String
    let value: String
    let level: BadgeLevel
    let target: SidebarItem?
}

struct OverviewView: View {
    @EnvironmentObject private var system: SystemInfoStore
    @EnvironmentObject private var battery: BatteryStore
    @Binding var selection: SidebarItem

    private var info: MacSystemInfo { system.info }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("设备概览", "Overview"),
                subtitle: T("本机硬件、电池与安全状态一次性核对", "Hardware, battery and security at a glance"),
                trailing: AnyView(
                    SecondaryButton(title: T("刷新", "Refresh"), icon: "arrow.clockwise") {
                        system.refresh()
                        battery.refresh()
                    }
                )
            )

            deviceCard
            consistencyCard
            originalityCard
            checksGrid
            if info.panicLogCount > 0 || info.storage.smartPercentageUsed != nil || info.storage.statisticsAvailable {
                healthSection
            }
            footerNote
        }
    }

    // MARK: - 设备卡片

    private var deviceCard: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                if let imageName = MacModelCatalog.imageName(for: info.modelIdentifier) {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 38, weight: .light))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 190, height: 116)

            VStack(alignment: .leading, spacing: 6) {
                Text(info.modelDisplayName)
                    .font(.system(size: 19, weight: .bold))
                Text(info.modelIdentifier)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    tag(info.chipName, icon: "cpu")
                    if info.memoryGB > 0 { tag("\(info.memoryGB) GB", icon: "memorychip") }
                    if info.storage.marketingCapacity != "—" {
                        tag(info.storage.marketingCapacity, icon: "internaldrive")
                    }
                }
                .padding(.top, 2)

                HStack(spacing: 6) {
                    Text(T("序列号", "Serial"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(info.serialNumber)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    if !info.serialValid {
                        StatusBadge(text: T("格式异常", "Unexpected format"), level: .warning)
                    }
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    // MARK: - 一致性核验

    private var consistencyCard: some View {
        let findings = ConsistencyAudit.run(info: info)
        let issues = findings.filter { $0.state == .inconsistent }.count
        let notices = findings.filter { $0.state == .notice }.count
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: T("一致性核验", "CONSISTENCY"))
                    Spacer()
                    StatusBadge(
                        text: issues > 0
                            ? T("\(issues) 项不一致", "\(issues) mismatch(es)")
                            : (notices > 0 ? T("\(notices) 项需确认", "\(notices) to confirm") : T("全部一致", "All consistent")),
                        level: issues > 0 ? .critical : (notices > 0 ? .warning : .ok)
                    )
                }

                Text(T("同一项事实分别从系统报告与内核接口读取，两路结果必须一致。改机型、刷序列号会在这里暴露。",
                       "Each fact is read from two independent sources — the system report and the kernel interface. Tampered model or serial data shows up here."))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(findings) { finding in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: finding.state.symbol)
                            .font(.system(size: 11))
                            .foregroundColor(color(for: finding.state))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(finding.title).font(.system(size: 11.5, weight: .medium))
                            Text(finding.detail).font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func color(for state: AuditState) -> Color {
        switch state {
        case .consistent: return .green
        case .notice: return .orange
        case .inconsistent: return .red
        case .unavailable: return .secondary
        }
    }

    // MARK: - 原装性核对

    private var originalityCard: some View {
        let findings = OriginalityCheck.run(info: info, battery: battery.battery)
        let issues = findings.filter { $0.state == .inconsistent }.count
        let notices = findings.filter { $0.state == .notice }.count
        let hasBaseline = ModelSpecCatalog.spec(for: info.modelIdentifier) != nil

        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: T("原装性核对", "ORIGINALITY"))
                    Spacer()
                    StatusBadge(
                        text: !hasBaseline
                            ? T("无对照数据", "No baseline")
                            : (issues > 0
                                ? T("\(issues) 项与规格不符", "\(issues) off-spec")
                                : (notices > 0 ? T("\(notices) 项需确认", "\(notices) to confirm") : T("符合官方规格", "Matches Apple spec"))),
                        level: !hasBaseline ? .neutral
                            : (issues > 0 ? .critical : (notices > 0 ? .warning : .ok))
                    )
                }

                Text(T("屏幕、内存、存储、电池规格与 Apple 官方技术规格比对。不匹配只代表「与官方规格不符」，不代表一定被改装过——维修换板也会造成同样结果。",
                       "Display, memory, storage and battery are compared against Apple's published tech specs. A mismatch means \"not matching Apple's spec\", not proof of modification — a board-level repair would look the same."))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(findings) { finding in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: finding.state.symbol)
                            .font(.system(size: 11))
                            .foregroundColor(color(for: finding.state))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(finding.title).font(.system(size: 11.5, weight: .medium))
                            Text(finding.detail).font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }

                if let spec = ModelSpecCatalog.spec(for: info.modelIdentifier) {
                    Text(T("规格基线：\(spec.name) · \(ModelSpecCatalog.coverageText) · \(spec.source)",
                           "Spec baseline: \(spec.name) · \(ModelSpecCatalog.coverageText) · \(spec.source)"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func tag(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(5)
    }

    // MARK: - 检查项网格

    private var checksGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: T("关键检查项", "KEY CHECKS"))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(checkItems.enumerated()), id: \.offset) { _, item in
                    checkRow(item)
                }
            }
        }
    }

    private func checkRow(_ item: CheckItem) -> some View {
        Button(action: {
            if let target = item.target { selection = target }
        }) {
            HStack(spacing: 10) {
                Image(systemName: item.level.symbol)
                    .font(.system(size: 14))
                    .foregroundColor(item.level.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 12, weight: .medium)).foregroundColor(.primary)
                    Text(item.value).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if item.target != nil {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary.opacity(0.6))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.05), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var checkItems: [CheckItem] {
        var items: [CheckItem] = []

        if battery.battery.isPresent {
            if let health = battery.battery.healthPercent {
                items.append(CheckItem(
                    title: T("电池健康度", "Battery health"),
                    value: "\(String(format: "%.1f", health))% · \(battery.battery.cycleCount) \(T("次循环", "cycles"))",
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
        switch battery.battery.healthGrade {
        case .excellent, .good: return .ok
        case .fair: return .warning
        case .service: return .critical
        case .unknown: return .neutral
        }
    }

    // MARK: - 健康区域

    private var healthSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: T("使用强度", "USAGE"))
                HStack(spacing: 24) {
                    if info.panicLogCount > 0 {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(T("崩溃日志", "Panic logs")).font(.system(size: 11)).foregroundColor(.secondary)
                            Text("\(info.panicLogCount)")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                            if let date = info.lastPanicDate {
                                Text(Format.dateTime(date))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    if let smartUsed = info.storage.smartPercentageUsed {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(T("SSD 已用寿命", "SSD wear")).font(.system(size: 11)).foregroundColor(.secondary)
                            Text("\(smartUsed)%")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(smartUsed > 50 ? .orange : .primary)
                        }
                    }
                    if info.storage.statisticsAvailable {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(T("累计写入", "Total written")).font(.system(size: 11)).foregroundColor(.secondary)
                            Text(Format.bytes(info.storage.writtenBytes))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var footerNote: some View {
        NoticeBar(
            text: T("所有数据均来自本机 IOKit、sysctl 与系统命令，不修改任何系统设置。取不到的项显示「不可用」或「无法读取」，不会用 0 或估算值代替。",
                   "All values come from IOKit, sysctl and read-only system commands. Nothing is modified. Missing values are shown as unavailable or unreadable — never replaced with 0 or an estimate."),
            level: .neutral
        )
    }
}
