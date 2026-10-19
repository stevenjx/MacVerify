// Views/LoadTestView.swift
import SwiftUI

struct LoadTestView: View {
    @EnvironmentObject private var batteryStore: BatteryStore
    @StateObject private var engine = BatteryLoadTest()
    @State private var duration = 600

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("电池负载测试", "Battery Load Test"),
                subtitle: T("真实放电采样，验证容量衰减与内阻表现", "Real discharge sampling to validate capacity loss and internal resistance")
            )

            if batteryStore.battery.isPluggedIn {
                NoticeBar(
                    text: T("当前已连接电源，负载压降无法测量。拔掉电源后测试可获得完整数据。",
                           "The Mac is on AC power, so voltage sag cannot be measured. Unplug the charger for complete results."),
                    level: .warning
                )
            }

            controlCard
            explainCard
            if engine.isRunning || !engine.voltageSeries.isEmpty {
                liveCard
            }
            if let result = engine.currentResult {
                resultCard(result)
            }
            historyCard

            NoticeBar(
                text: T("测试会持续占用 CPU 并让电池放电，请先保存工作。接电源时压降不可测，建议拔掉电源后测试。",
                       "The test keeps the CPU busy and drains the battery — save your work first. Voltage sag cannot be measured on AC power, so unplug the charger."),
                level: .warning
            )
        }
    }

    private var controlCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: T("测试设置", "SETUP"))

                HStack(spacing: 10) {
                    ForEach([180, 600, 1200], id: \.self) { seconds in
                        Button(action: { duration = seconds }) {
                            Text(durationLabel(seconds))
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(duration == seconds ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                                .foregroundColor(duration == seconds ? .accentColor : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(engine.isRunning)
                    }
                    Spacer()

                    if engine.isRunning {
                        SecondaryButton(title: T("停止", "Stop"), icon: "stop.fill") { engine.stop() }
                    } else {
                        PrimaryButton(title: T("开始测试", "Start test"), icon: "play.fill", enabled: batteryStore.battery.isPresent) {
                            engine.start(seconds: duration)
                        }
                    }
                }

                if engine.isRunning {
                    ProgressView(value: engine.progress).progressViewStyle(.linear)
                    Text(engine.status).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                }
            }
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        switch seconds {
        case 180: return T("3 分钟", "3 min")
        case 600: return T("10 分钟", "10 min")
        default: return T("20 分钟", "20 min")
        }
    }

    private var explainCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: T("测试内容", "WHAT IT MEASURES"))
                explainRow(icon: "battery.100", text: T("满充容量与设计容量的比值，以及循环次数是否与衰减吻合。",
                                                       "Full charge capacity against design capacity, and whether cycle count matches the wear."))
                explainRow(icon: "bolt", text: T("持续负载下的电压下沉幅度，可反映电池内阻。仅在电池供电时有效。",
                                                 "Voltage sag under sustained load, which reflects internal resistance. Only valid on battery power."))
                explainRow(icon: "thermometer", text: T("电池温升。部分机型不提供温度传感器，该项会标记为不可用。",
                                                        "Battery temperature rise. Some models do not expose a sensor; the item is then marked unavailable."))
            }
        }
    }

    private func explainRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var liveCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: T("实时采样", "LIVE SAMPLES"))
                    Spacer()
                    Text(T("\(engine.samples) 个采样点", "\(engine.samples) samples"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(T("电压 (V)", "Voltage (V)")).font(.system(size: 10)).foregroundColor(.secondary)
                    LineChart(values: engine.voltageSeries, color: .orange)
                        .frame(height: 110)
                }

                if !engine.temperatureSeries.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(T("电池温度 (°C)", "Battery temperature (°C)")).font(.system(size: 10)).foregroundColor(.secondary)
                        LineChart(values: engine.temperatureSeries, color: .red)
                            .frame(height: 90)
                    }
                }
            }
        }
    }

    private func resultCard(_ result: BatteryAuditResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(result.score) / 100)
                            .stroke(scoreColor(result.score), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(result.score)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.verdict).font(.system(size: 14, weight: .semibold))
                        Text(T("测试时长 \(Int(result.duration)) 秒 · \(result.findings.count) 项检查",
                               "\(Int(result.duration))s · \(result.findings.count) checks"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                ForEach(result.findings) { finding in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: finding.status.symbol)
                            .font(.system(size: 11))
                            .foregroundColor(color(for: finding.status))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(finding.title).font(.system(size: 11.5, weight: .medium))
                            Text(finding.detail).font(.system(size: 10)).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: T("记录", "HISTORY"))
                let store = AuditHistoryStore.shared
                if store.results.isEmpty {
                    Text(T("暂无记录", "No records")).font(.system(size: 11)).foregroundColor(.secondary)
                } else {
                    ForEach(store.results.prefix(8)) { item in
                        HStack {
                            Text(Format.dateTime(item.date))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(item.score)").font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(scoreColor(item.score))
                            Text(item.verdict).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Divider().opacity(0.4)
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

    private func color(for status: FindingStatus) -> Color {
        switch status {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        case .info: return .secondary
        }
    }
}
