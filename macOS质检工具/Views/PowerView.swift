// Views/PowerView.swift
import SwiftUI
import AppKit

struct PowerView: View {
    @EnvironmentObject private var batteryStore: BatteryStore

    private var battery: BatterySnapshot { batteryStore.battery }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("供电", "Power"),
                subtitle: T("适配器、充电状态与电池功率", "Adapter, charging state and battery power")
            )

            HStack(alignment: .top, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: T("充电状态", "CHARGING"))
                        HStack(spacing: 14) {
                            RingGauge(
                                title: T("电量", "Charge"),
                                value: battery.percent,
                                total: 100,
                                unit: "%",
                                color: battery.percent > 20 ? .green : .orange
                            )
                            VStack(alignment: .leading, spacing: 6) {
                                Text(chargingStateText)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(battery.isPluggedIn
                                     ? T("已连接电源适配器", "Power adapter connected")
                                     : T("正在使用电池供电", "Running on battery"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                if let empty = battery.timeToEmpty, !battery.isPluggedIn {
                                    Text(T("预计可用 \(empty / 60) 小时 \(empty % 60) 分钟", "About \(empty / 60)h \(empty % 60)m remaining"))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                if let full = battery.timeToFull, battery.isPluggedIn, !battery.isFullyCharged {
                                    Text(T("预计 \(full) 分钟后充满", "Full in about \(full) min"))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: T("适配器", "ADAPTER"))
                        if let watts = battery.adapterWatts {
                            Text("\(watts) W")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                            Text(battery.adapterName ?? T("USB-C 电源适配器", "USB-C power adapter"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            if let manufacturer = battery.adapterManufacturer {
                                Text(manufacturer).font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        } else {
                            Text(T("未检测到适配器", "No adapter detected"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(T("使用电池供电时无法读取适配器信息。", "Adapter details are unavailable while running on battery."))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: T("电池实时参数", "LIVE VALUES"))
                    HStack(spacing: 12) {
                        StatTile(title: T("电压", "Voltage"),
                                 value: battery.voltage > 0 ? String(format: "%.2f V", battery.voltage) : "—",
                                 color: .accentColor, icon: "bolt")
                        StatTile(title: T("电流", "Current"),
                                 value: String(format: "%+.2f A", battery.amperage),
                                 detail: battery.amperage < 0 ? T("放电", "Discharging") : (battery.amperage > 0 ? T("充电", "Charging") : T("无负载", "Idle")),
                                 color: .accentColor, icon: "arrow.left.arrow.right")
                        StatTile(title: T("功率", "Power"),
                                 value: String(format: "%.1f W", abs(battery.voltage * battery.amperage)),
                                 color: .accentColor, icon: "gauge")
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: T("充电管理", "CHARGE MANAGEMENT"))
                    Text(T("macOS 会在系统设置中提供“优化电池充电”和充电上限（部分机型）。第三方应用无法安全地改写充电阈值，本工具只读取状态，不修改系统设置。",
                           "macOS manages Optimized Battery Charging and, on some models, a charge limit in System Settings. Third-party apps cannot safely override these thresholds, so MacCheck only reads the state."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SecondaryButton(title: T("打开电池设置", "Open Battery settings"), icon: "arrow.up.forward.app") {
                        openBatterySettings()
                    }
                }
            }
        }
    }

    private var chargingStateText: String {
        if battery.permanentFailure { return T("电池故障", "Battery fault") }
        if battery.isFullyCharged { return T("已充满", "Fully charged") }
        if battery.isCharging { return T("正在充电", "Charging") }
        if battery.isPluggedIn { return T("已接电源，未充电", "On power, not charging") }
        return T("使用电池", "On battery")
    }

    private func openBatterySettings() {
        let identifiers = [
            "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.battery"
        ]
        for identifier in identifiers {
            if let url = URL(string: identifier), NSWorkspace.shared.open(url) { return }
        }
    }
}
