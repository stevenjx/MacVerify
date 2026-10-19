// Views/BatteryView.swift
import SwiftUI

struct BatteryView: View {
    @EnvironmentObject private var batteryStore: BatteryStore
    @StateObject private var history = AuditHistoryStore.shared

    private var battery: BatterySnapshot { batteryStore.battery }

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
                gaugeRow
                detailCard
                powerCard
                historyCard
            } else {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "battery.0").font(.system(size: 24)).foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(T("未检测到电池", "No battery detected")).font(.system(size: 13, weight: .medium))
                            Text(T("台式 Mac 或电池未连接时无法读取电池数据。", "Desktop Macs or a disconnected battery have no battery data."))
                                .font(.system(size: 11)).foregroundColor(.secondary)
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

    // MARK: - 顶部仪表

    private var gaugeRow: some View {
        HStack(spacing: 16) {
            RingGauge(
                title: T("电池健康度", "Health"),
                value: battery.healthPercent ?? 0,
                total: 100,
                unit: "%",
                color: healthColor,
                caption: batteryStore.healthCategory.text
            )
            .padding(.vertical, 10)

            StatTile(title: T("循环次数", "Cycle count"),
                     value: "\(battery.cycleCount)",
                     detail: T("设计上限 \(battery.designCycleCount) 次", "Design limit \(battery.designCycleCount)"),
                     color: .accentColor, icon: "arrow.triangle.2.circlepath")
            StatTile(title: T("当前电量", "Charge"),
                     value: String(format: "%.0f%%", battery.percent),
                     detail: battery.isCharging ? T("正在充电", "Charging") : (battery.isPluggedIn ? T("已接电源", "On power") : T("使用电池", "On battery")),
                     color: .green, icon: "bolt")
            StatTile(title: T("满充容量", "Full charge"),
                     value: battery.healthCapacity > 0 ? "\(battery.healthCapacity) mAh" : "—",
                     detail: battery.designCapacity > 0 ? T("设计 \(battery.designCapacity) mAh", "Design \(battery.designCapacity) mAh") : nil,
                     color: .purple, icon: "battery.100")
        }
    }

    private var healthColor: Color {
        guard let health = battery.healthPercent else { return .secondary }
        if health >= 85 { return .green }
        if health >= 75 { return .orange }
        return .red
    }

    // MARK: - 详情

    private var detailCard: some View {
        Card {
            VStack(spacing: 0) {
                SectionHeader(title: T("电池信息", "BATTERY INFO")).padding(.bottom, 8)
                InfoRow(label: T("序列号", "Serial"), value: battery.serialNumber, monospaced: true)
                InfoRow(label: T("制造商", "Manufacturer"), value: battery.manufacturer)
                InfoRow(label: T("设计容量", "Design capacity"), value: battery.designCapacity > 0 ? "\(battery.designCapacity) mAh" : T("不可用", "Unavailable"))
                InfoRow(label: T("当前满充容量", "Full charge capacity"), value: battery.healthCapacity > 0 ? "\(battery.healthCapacity) mAh" : T("不可用", "Unavailable"))
                InfoRow(label: T("剩余容量", "Remaining"), value: battery.remainingCapacity > 0 ? "\(battery.remainingCapacity) mAh" : "—")
                InfoRow(label: T("永久性故障", "Permanent failure"),
                        value: battery.permanentFailure ? T("是", "Yes") : T("否", "No"),
                        valueColor: battery.permanentFailure ? .red : .primary)
                InfoRow(label: T("电压", "Voltage"), value: battery.voltage > 0 ? String(format: "%.2f V", battery.voltage) : "—")
                InfoRow(label: T("电流", "Current"), value: String(format: "%+.2f A", battery.amperage))
                InfoRow(label: T("温度", "Temperature"),
                        value: battery.temperature.map { String(format: "%.1f °C", $0) } ?? T("该机型未公开", "Not exposed on this model"), isLast: true)
            }
        }
    }

    private var powerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: T("功率", "POWER"))
                HStack(spacing: 12) {
                    StatTile(title: T("瞬时功率", "Instant power"),
                             value: String(format: "%.1f W", abs(battery.voltage * battery.amperage)),
                             detail: T("电压 × 电流", "Voltage × current"),
                             color: .orange, icon: "bolt.fill")
                    if let resistance = batteryStore.resistanceMilliohms {
                        StatTile(title: T("内阻估算", "Est. resistance"),
                                 value: String(format: "%.0f mΩ", resistance),
                                 detail: T("基于 \(batteryStore.resistanceSamples) 组 ΔV/ΔI 采样", "From \(batteryStore.resistanceSamples) ΔV/ΔI samples"),
                                 color: resistance < 150 ? .green : .orange, icon: "waveform.path")
                    } else {
                        StatTile(title: T("内阻估算", "Est. resistance"),
                                 value: "—",
                                 detail: T("需要电流变化才能计算", "Needs a current change to compute"),
                                 color: .secondary, icon: "waveform.path")
                    }
                    StatTile(title: T("剩余时间", "Time remaining"),
                             value: battery.timeToEmpty.map { "\($0 / 60) h \($0 % 60) m" } ?? "—",
                             detail: battery.isPluggedIn ? T("充电至 \(battery.timeToFull ?? 0) 分钟", "Full in \(battery.timeToFull ?? 0) min") : T("系统估算", "System estimate"),
                             color: .secondary, icon: "clock")
                }
            }
        }
    }

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: T("负载测试记录", "LOAD TEST HISTORY"))
                    Spacer()
                    if !history.results.isEmpty {
                        SecondaryButton(title: T("清空", "Clear"), icon: "trash") { history.clear() }
                    }
                }

                if history.results.isEmpty {
                    Text(T("暂无记录。运行一次电池负载测试后会保存在这里。", "No records yet. Run a battery load test to create one."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(history.results.prefix(5)) { result in
                        HStack(spacing: 10) {
                            Text("\(result.score)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .frame(width: 32, height: 24)
                                .background(scoreColor(result.score).opacity(0.12))
                                .foregroundColor(scoreColor(result.score))
                                .cornerRadius(5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.verdict).font(.system(size: 11, weight: .medium))
                                Text(Format.dateTime(result.date))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let health = result.healthPercent {
                                Text(String(format: "%.1f%%", health))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return .green }
        if score >= 70 { return .orange }
        return .red
    }
}
