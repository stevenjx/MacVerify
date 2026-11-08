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

            HStack(alignment: .top, spacing: Metrics.pageGap) {
                Card(title: T("充电状态", "Charging"), icon: "bolt.circle") {
                    HStack(alignment: .center, spacing: Space.lg) {
                        RingGauge(
                            title: T("电量", "Charge"),
                            value: battery.percent,
                            total: 100,
                            unit: "%",
                            color: battery.percent > 20 ? StatusPalette.ok : StatusPalette.warning,
                            size: 84
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chargingStateText)
                                .font(Typo.title)
                            Text(battery.isPluggedIn
                                 ? T("已连接电源适配器", "Power adapter connected")
                                 : T("正在使用电池供电", "Running on battery"))
                                .font(Typo.caption)
                                .foregroundColor(.secondary)
                            if let empty = battery.timeToEmpty, !battery.isPluggedIn {
                                Text(T("预计可用 \(empty / 60) 小时 \(empty % 60) 分钟",
                                       "About \(empty / 60)h \(empty % 60)m remaining"))
                                    .font(Typo.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let full = battery.timeToFull, battery.isPluggedIn, !battery.isFullyCharged {
                                Text(T("预计 \(full) 分钟后充满", "Full in about \(full) min"))
                                    .font(Typo.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }

                Card(title: T("适配器", "Adapter"), icon: "powerplug") {
                    if let watts = battery.adapterWatts {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(watts)")
                                .font(Typo.metric)
                            Text("W").font(Typo.caption).foregroundColor(.secondary)
                        }
                        Text(battery.adapterName ?? T("USB-C 电源适配器", "USB-C power adapter"))
                            .font(Typo.caption)
                            .foregroundColor(.secondary)
                        if let manufacturer = battery.adapterManufacturer {
                            Text(manufacturer).font(Typo.caption).foregroundColor(.secondary)
                        }
                    } else {
                        Text(T("未检测到适配器", "No adapter detected"))
                            .font(Typo.body)
                            .foregroundColor(.secondary)
                        Text(T("使用电池供电时无法读取适配器信息。", "Adapter details are unavailable while running on battery."))
                            .font(Typo.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 300)
            }

            Card(title: T("电池实时参数", "Live values"), icon: "waveform.path") {
                HStack(spacing: Space.sm) {
                    StatTile(title: T("电压", "Voltage"),
                             value: battery.voltage > 0 ? String(format: "%.2f", battery.voltage) : "—",
                             unit: battery.voltage > 0 ? "V" : nil,
                             color: .secondary, icon: "bolt")
                    StatTile(title: T("电流", "Current"),
                             value: String(format: "%+.2f", battery.amperage), unit: "A",
                             detail: battery.amperage < 0 ? T("放电", "Discharging")
                                    : (battery.amperage > 0 ? T("充电", "Charging") : T("无负载", "Idle")),
                             color: .secondary, icon: "arrow.left.arrow.right")
                    StatTile(title: T("功率", "Power"),
                             value: String(format: "%.1f", abs(battery.voltage * battery.amperage)), unit: "W",
                             detail: T("电压 × 电流", "Voltage × current"),
                             color: .secondary, icon: "gauge")
                    StatTile(title: T("剩余时间", "Time left"),
                             value: battery.timeToEmpty.map { "\($0 / 60)h \($0 % 60)m" } ?? "—",
                             detail: battery.isPluggedIn ? T("接电源", "On power") : T("系统估算", "System estimate"),
                             color: .secondary, icon: "clock")
                }
            }

            Card(title: T("充电管理", "Charge management"), icon: "gearshape",
                 trailing: AnyView(
                    SecondaryButton(title: T("打开电池设置", "Open Battery settings"), icon: "arrow.up.forward.app") {
                        openBatterySettings()
                    }
                 )) {
                Text(T("macOS 会在系统设置中提供“优化电池充电”和充电上限（部分机型）。第三方应用无法安全地改写充电阈值，本工具只读取状态，不修改系统设置。",
                       "macOS manages Optimized Battery Charging and, on some models, a charge limit in System Settings. Third-party apps cannot safely override these thresholds, so MacVerify only reads the state."))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
