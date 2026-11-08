// Views/BatteryView.swift
//
// 电池：健康与信息并排，功率与历史各一行。
// 改造前是仪表一行 + 三张竖卡，信息密度低、右侧空。
import SwiftUI

struct BatteryView: View {
    @EnvironmentObject private var batteryStore: BatteryStore
    @StateObject private var history = AuditHistoryStore.shared

    private var battery: BatterySnapshot { batteryStore.battery }

    private var infoFacts: [Fact] {
        [
            Fact(T("序列号", "Serial"), battery.serialNumber, mono: true),
            Fact(T("计量芯片", "Gauge chip"),
                 battery.gaugeModel.isEmpty ? T("不可用", "Unavailable") : battery.gaugeModel,
                 mono: true, state: battery.gaugeModel.isEmpty ? .unavailable : .normal),
            Fact(T("设计容量", "Design capacity"),
                 battery.designCapacity > 0 ? "\(battery.designCapacity) mAh" : T("不可用", "Unavailable"),
                 state: battery.designCapacity > 0 ? .normal : .unavailable),
            Fact(T("满充容量", "Full charge"),
                 battery.healthCapacity > 0 ? "\(battery.healthCapacity) mAh" : T("不可用", "Unavailable"),
                 state: battery.healthCapacity > 0 ? .normal : .unavailable),
            Fact(T("剩余容量", "Remaining"),
                 battery.remainingCapacity > 0 ? "\(battery.remainingCapacity) mAh" : T("无数据", "None"),
                 state: battery.remainingCapacity > 0 ? .normal : .absent),
            Fact(T("永久性故障", "Permanent failure"),
                 battery.permanentFailure ? T("是", "Yes") : T("否", "No"),
                 color: battery.permanentFailure ? StatusPalette.critical : .primary),
            Fact(T("电压", "Voltage"), battery.voltage > 0 ? String(format: "%.2f V", battery.voltage) : "—"),
            Fact(T("电流", "Current"), String(format: "%+.2f A", battery.amperage)),
            Fact(T("温度", "Temperature"),
                 battery.temperature.map { String(format: "%.1f °C", $0) } ?? T("该机型未公开", "Not exposed"),
                 state: battery.temperature == nil ? .unavailable : .normal)
        ]
    }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("电池", "Battery"),
                subtitle: T("容量、循环、温度与瞬时功率", "Capacity, cycles, temperature and live power draw"),
                trailing: AnyView(
                    SecondaryButton(title: T("刷新", "Refresh"), icon: "arrow.clockwise") { batteryStore.refresh() }
                )
            )

            if battery.isPresent {
                HStack(alignment: .top, spacing: Metrics.pageGap) {
                    healthCard.frame(width: 330)
                    Card(title: T("电池信息", "Battery info"), icon: "battery.100") {
                        FactGrid(facts: infoFacts, columns: 2, labelWidth: 84)
                    }
                }
                powerCard
                historyCard
            } else {
                Card {
                    HStack(spacing: Space.md) {
                        Image(systemName: "battery.0").font(Typo.icon(22)).foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(T("未检测到电池", "No battery detected")).font(Typo.body)
                            Text(T("台式 Mac 或电池未连接时无法读取电池数据。", "Desktop Macs or a disconnected battery have no battery data."))
                                .font(Typo.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            NoticeBar(
                text: T("健康度按 Apple 口径计算：当前满充容量 ÷ 设计容量。数值在 80% 以上通常无需处理。",
                       "Health follows Apple's definition: full charge capacity ÷ design capacity. Above 80% no action is usually needed."),
                level: .neutral
            )
        }
    }

    // MARK: - 健康

    private var healthCard: some View {
        Card(title: T("健康", "Health"), icon: "heart", trailing: AnyView(
            StatusBadge(text: batteryStore.healthCategory.text, level: badgeLevel)
        )) {
            HStack(alignment: .center, spacing: Space.lg) {
                RingGauge(
                    title: T("最大容量", "Max capacity"),
                    value: battery.healthPercent ?? 0,
                    total: 100,
                    unit: "%",
                    color: healthColor,
                    size: 84
                )

                VStack(spacing: Space.sm) {
                    HStack(spacing: Space.sm) {
                        StatTile(title: T("循环次数", "Cycles"),
                                 value: "\(battery.cycleCount)",
                                 detail: T("设计上限 \(battery.designCycleCount)", "Limit \(battery.designCycleCount)"),
                                 color: .secondary, icon: "arrow.triangle.2.circlepath")
                        StatTile(title: T("当前电量", "Charge"),
                                 value: String(format: "%.0f", battery.percent), unit: "%",
                                 detail: battery.isCharging ? T("充电中", "Charging")
                                        : (battery.isPluggedIn ? T("接电源", "On power") : T("用电池", "On battery")),
                                 color: StatusPalette.ok, icon: "bolt")
                    }
                    HStack(spacing: Space.sm) {
                        StatTile(title: T("设计容量", "Design"),
                                 value: battery.designCapacity > 0 ? "\(battery.designCapacity)" : "—",
                                 unit: battery.designCapacity > 0 ? "mAh" : nil,
                                 color: .secondary, icon: "battery.25")
                        StatTile(title: T("满充容量", "Full charge"),
                                 value: battery.healthCapacity > 0 ? "\(battery.healthCapacity)" : "—",
                                 unit: battery.healthCapacity > 0 ? "mAh" : nil,
                                 color: .secondary, icon: "battery.100")
                    }
                }
            }
        }
    }

    private var badgeLevel: BadgeLevel {
        switch battery.healthGrade {
        case .excellent, .good: return .ok
        case .fair: return .warning
        case .service: return .critical
        case .unknown: return .neutral
        }
    }

    private var healthColor: Color {
        switch battery.healthGrade {
        case .excellent, .good: return StatusPalette.ok
        case .fair: return StatusPalette.warning
        case .service: return StatusPalette.critical
        case .unknown: return .secondary
        }
    }

    // MARK: - 功率

    private var powerCard: some View {
        Card(title: T("功率", "Power"), icon: "bolt") {
            HStack(spacing: Space.sm) {
                StatTile(title: T("瞬时功率", "Instant power"),
                         value: String(format: "%.1f", abs(battery.voltage * battery.amperage)), unit: "W",
                         detail: T("电压 × 电流", "Voltage × current"),
                         color: StatusPalette.warning, icon: "bolt.fill")
                if let resistance = batteryStore.resistanceMilliohms {
                    StatTile(title: T("内阻估算", "Est. resistance"),
                             value: String(format: "%.0f", resistance), unit: "mΩ",
                             detail: T("基于 \(batteryStore.resistanceSamples) 组 ΔV/ΔI 采样",
                                       "From \(batteryStore.resistanceSamples) ΔV/ΔI samples"),
                             color: resistance < 150 ? StatusPalette.ok : StatusPalette.warning,
                             icon: "waveform.path")
                } else {
                    StatTile(title: T("内阻估算", "Est. resistance"), value: "—",
                             placeholder: true,
                             detail: T("需要电流变化才能计算", "Needs a current change"),
                             color: .secondary, icon: "waveform.path")
                }
                StatTile(title: T("剩余时间", "Time remaining"),
                         value: battery.timeToEmpty.map { "\($0 / 60) h \($0 % 60) m" } ?? "—",
                         placeholder: battery.timeToEmpty == nil,
                         detail: remainingTimeDetail,
                         color: .secondary, icon: "clock")
                StatTile(title: T("温度", "Temperature"),
                         value: battery.temperature.map { String(format: "%.1f", $0) } ?? "—",
                         unit: battery.temperature == nil ? nil : "°C",
                         placeholder: battery.temperature == nil,
                         detail: battery.temperature == nil ? T("该机型未公开", "Not exposed") : T("来自电池管理芯片", "From the gauge"),
                         color: .secondary, icon: "thermometer")
            }
        }
    }

    private var remainingTimeDetail: String? {
        if battery.timeToEmpty != nil { return T("系统估算", "System estimate") }
        if battery.isPluggedIn, let full = battery.timeToFull, full > 0 {
            return T("充电至 \(full) 分钟", "Full in \(full) min")
        }
        return nil
    }

    // MARK: - 历史

    private var historyCard: some View {
        Card(title: T("负载测试记录", "Load test history"), icon: "clock.arrow.circlepath",
             trailing: AnyView(
                Group {
                    if !history.results.isEmpty {
                        SecondaryButton(title: T("清空", "Clear"), icon: "trash") { history.clear() }
                    }
                }
             )) {
            if history.results.isEmpty {
                Text(T("暂无记录。运行一次电池负载测试后会保存在这里。", "No records yet. Run a battery load test to create one."))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.results.prefix(5).enumerated()), id: \.element.id) { index, result in
                        HStack(spacing: Space.sm) {
                            Text("\(result.score)")
                                .font(Typo.captionStrong)
                                .frame(width: 30, height: 20)
                                .background(ScorePalette.color(result.score).opacity(0.12))
                                .foregroundColor(ScorePalette.color(result.score))
                                .cornerRadius(4)
                            Text(result.verdict).font(Typo.caption)
                            Spacer()
                            if let health = result.healthPercent {
                                Text(String(format: "%.1f%%", health))
                                    .font(Typo.mono)
                                    .foregroundColor(.secondary)
                            }
                            Text(Format.dateTime(result.date))
                                .font(Typo.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: Metrics.row)
                        if index < min(history.results.count, 5) - 1 {
                            Rectangle().fill(Surface.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}
