// Views/Overview/OverviewStatusCards.swift
//
// 概览页右列三张状态卡：系统运行、电池控制器、安全。
// 每行只回答一个问题，值贴右对齐；读不到的项写「无法读取」，与「已关闭」区分开。
import SwiftUI

struct OverviewStatusCards: View {
    let info: MacSystemInfo
    let battery: BatterySnapshot

    var body: some View {
        VStack(spacing: Metrics.pageGap) {
            card(T("系统运行状态", "System status"), icon: "gauge", rows: systemRows)
            card(T("电池控制器信息", "Battery controller"), icon: "battery.75", rows: batteryRows)
            card(T("安全状态", "Security"), icon: "lock.shield", rows: securityRows)
        }
        .frame(width: 300)
    }

    // MARK: - 卡

    private func card(_ title: String, icon: String, rows: [StatusRow]) -> some View {
        Card(title: title, icon: icon) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Space.sm) {
                        Text(row.label)
                            .font(Typo.body)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: Space.sm)

                        if row.state == .normal {
                            Text(row.value)
                                .font(Typo.value)
                                .foregroundColor(row.color)
                                .lineLimit(1)
                                .help(row.value)
                        } else {
                            HStack(spacing: 3) {
                                Image(systemName: row.state == .unavailable ? "minus.circle" : "slash.circle")
                                    .font(Typo.icon(9))
                                Text(row.value).font(Typo.body)
                            }
                            .foregroundColor(StatusPalette.neutral)
                        }
                    }
                    .frame(height: 24)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.label)：\(row.value)")
                }
            }
        }
    }

    // MARK: - 系统运行状态

    private var systemRows: [StatusRow] {
        var rows: [StatusRow] = [
            StatusRow(label: T("系统版本", "macOS"), value: "\(info.osVersion) (\(info.osBuild))"),
            StatusRow(label: T("运行时间", "Uptime"), value: info.systemUptimeText)
        ]

        switch info.storage.isInternalDisk {
        case .some(true): rows.append(StatusRow(label: T("启动磁盘", "Boot disk"), value: T("内建", "Internal")))
        case .some(false): rows.append(StatusRow(label: T("启动磁盘", "Boot disk"),
                                                 value: T("外接", "External"), color: StatusPalette.warning))
        case .none: rows.append(unavailableRow(T("启动磁盘", "Boot disk")))
        }

        if !info.panicScanAvailable {
            rows.append(unavailableRow(T("崩溃记录", "Kernel panics")))
        } else if info.panicLogCount > 0 {
            rows.append(StatusRow(label: T("崩溃记录", "Kernel panics"),
                                  value: T("\(info.panicLogCount) 条", "\(info.panicLogCount) records"),
                                  color: StatusPalette.warning))
        } else {
            rows.append(StatusRow(label: T("崩溃记录", "Kernel panics"),
                                  value: T("无记录", "None"), color: StatusPalette.ok))
        }

        return rows
    }

    // MARK: - 电池控制器信息

    private var batteryRows: [StatusRow] {
        guard battery.isPresent else {
            return [StatusRow(label: T("电池", "Battery"),
                              value: T("未检测到电池", "No battery detected"),
                              color: StatusPalette.neutral,
                              state: .absent)]
        }

        var rows: [StatusRow] = []

        if battery.cycleCountAvailable {
            rows.append(StatusRow(label: T("充电循环次数", "Cycle count"),
                                  value: T("\(battery.cycleCount) 次", "\(battery.cycleCount) cycles")))
        } else {
            rows.append(unavailableRow(T("充电循环次数", "Cycle count")))
        }

        if let health = battery.healthPercent {
            rows.append(StatusRow(label: T("电池健康度", "Battery health"),
                                  value: String(format: "%.0f%%", health),
                                  color: healthColor))
        } else {
            rows.append(unavailableRow(T("电池健康度", "Battery health")))
        }

        rows.append(StatusRow(label: T("电池状态", "State"), value: powerStateText, color: powerStateColor))

        if battery.manufacturer.isEmpty || battery.manufacturer == "—" {
            rows.append(StatusRow(label: T("电池制造商", "Manufacturer"),
                                  value: T("不可用", "Unavailable"),
                                  color: StatusPalette.neutral,
                                  state: .unavailable))
        } else {
            rows.append(StatusRow(label: T("电池制造商", "Manufacturer"), value: battery.manufacturer))
        }
        return rows
    }

    private var healthColor: Color {
        switch battery.healthGrade {
        case .excellent, .good: return StatusPalette.ok
        case .fair: return StatusPalette.warning
        case .service: return StatusPalette.critical
        case .unknown: return StatusPalette.neutral
        }
    }

    private var powerStateText: String {
        if battery.isCharging { return T("充电中", "Charging") }
        if battery.isFullyCharged { return T("已充满", "Charged") }
        if battery.isPluggedIn { return T("已接通电源", "On power adapter") }
        return T("使用电池", "On battery")
    }

    private var powerStateColor: Color {
        battery.isCharging || battery.isFullyCharged ? StatusPalette.ok : .primary
    }

    // MARK: - 安全状态

    private var securityRows: [StatusRow] {
        [
            triStateRow(T("激活锁", "Activation Lock"),
                        value: info.activationLock,
                        on: T("已开启", "Enabled"), onColor: StatusPalette.warning,
                        off: T("已关闭", "Disabled"), offColor: StatusPalette.ok),

            triStateRow(T("文件保险箱", "FileVault"),
                        value: info.fileVault,
                        on: T("已加密", "Encrypted"), onColor: StatusPalette.ok,
                        off: T("未加密", "Not encrypted"), offColor: StatusPalette.neutral),

            triStateRow(T("MDM 描述文件", "MDM profile"),
                        value: info.mdmEnrolled,
                        on: T("已注册", "Enrolled"), onColor: StatusPalette.warning,
                        off: T("未注册", "Not enrolled"), offColor: StatusPalette.ok),

            triStateRow(T("系统完整性保护", "System Integrity"),
                        value: info.sipEnabled,
                        on: T("已启用", "Enabled"), onColor: StatusPalette.ok,
                        off: T("已停用", "Disabled"), offColor: StatusPalette.warning)
        ]
    }

    private func triStateRow(_ label: String, value: Bool?,
                             on: String, onColor: Color,
                             off: String, offColor: Color) -> StatusRow {
        guard let value = value else { return unavailableRow(label) }
        return StatusRow(label: label, value: value ? on : off, color: value ? onColor : offColor)
    }

    // MARK: - 通用

    private func unavailableRow(_ label: String) -> StatusRow {
        StatusRow(label: label,
                  value: T("无法读取", "Unreadable"),
                  color: StatusPalette.neutral,
                  state: .unavailable)
    }
}

private struct StatusRow {
    let label: String
    let value: String
    var color: Color = .primary
    var state: ValueState = .normal
}
