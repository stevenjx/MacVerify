// Views/LoadTestView.swift
//
// 负载测试：设置与说明并排，图表左右并列，结果与记录各一行。
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

            HStack(alignment: .top, spacing: Metrics.pageGap) {
                controlCard.frame(width: 380)
                explainCard
            }

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
        .onChange(of: engine.currentResult != nil) { done in
            if done { TestProgress.shared.markCompleted("loadTest") }
        }
    }

    private var controlCard: some View {
        Card(title: T("测试设置", "Setup"), icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    SegmentedPicker(options: [180, 600, 1200],
                                    title: durationLabel,
                                    selection: $duration,
                                    enabled: !engine.isRunning)
                    Spacer(minLength: 0)
                    if engine.isRunning {
                        SecondaryButton(title: T("停止", "Stop"), icon: "stop.fill") { engine.stop() }
                    } else {
                        PrimaryButton(title: T("开始测试", "Start test"), icon: "play.fill",
                                      enabled: batteryStore.battery.isPresent) {
                            engine.start(seconds: duration)
                        }
                    }
                }

                if engine.isRunning {
                    ProgressView(value: engine.progress).progressViewStyle(.linear)
                }
                Text(engine.status).font(Typo.caption).foregroundColor(.secondary)
            }
        }
        .onDisappear {
            engine.stop()
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
        Card(title: T("测试内容", "What it measures"), icon: "list.bullet") {
            VStack(alignment: .leading, spacing: Space.sm) {
                explainRow(icon: "battery.100",
                           text: T("满充容量与设计容量的比值，以及循环次数是否与衰减吻合。",
                                   "Full charge capacity against design capacity, and whether cycle count matches the wear."))
                explainRow(icon: "bolt",
                           text: T("持续负载下的电压下沉幅度，可反映电池内阻。仅在电池供电时有效。",
                                   "Voltage sag under sustained load, which reflects internal resistance. Only valid on battery power."))
                explainRow(icon: "thermometer",
                           text: T("电池温升。部分机型不提供温度传感器，该项会标记为不可用。",
                                   "Battery temperature rise. Some models do not expose a sensor; the item is then marked unavailable."))
            }
        }
    }

    private func explainRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: icon)
                .font(Typo.icon(10))
                .foregroundColor(.secondary)
                .frame(width: 14)
            Text(text)
                .font(Typo.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var liveCard: some View {
        Card(title: T("实时采样", "Live samples"), icon: "waveform.path.ecg",
             trailing: AnyView(
                Text(T("\(engine.samples) 个采样点", "\(engine.samples) samples"))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
             )) {
            HStack(alignment: .top, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(T("电压 (V)", "Voltage (V)")).font(Typo.caption).foregroundColor(.secondary)
                    LineChart(values: engine.voltageSeries, color: Color.accentColor)
                        .frame(height: 100)
                }
                if !engine.temperatureSeries.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(T("电池温度 (°C)", "Battery temperature (°C)"))
                            .font(Typo.caption).foregroundColor(.secondary)
                        LineChart(values: engine.temperatureSeries, color: StatusPalette.warning)
                            .frame(height: 100)
                    }
                }
            }
        }
    }

    private func resultCard(_ result: BatteryAuditResult) -> some View {
        Card(title: T("本次结果", "This run"), icon: "checklist",
             trailing: AnyView(
                StatusBadge(text: result.verdict, level: result.score >= 85 ? .ok : (result.score >= 70 ? .warning : .critical))
             )) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .center, spacing: Space.md) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: CGFloat(result.score) / 100)
                            .stroke(ScorePalette.color(result.score), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(result.score)")
                            .font(Typo.metric)
                    }
                    .frame(width: 58, height: 58)

                    Text(T("测试时长 \(Int(result.duration)) 秒 · \(result.findings.count) 项检查",
                           "\(Int(result.duration))s · \(result.findings.count) checks"))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                VStack(spacing: 0) {
                    ForEach(Array(result.findings.enumerated()), id: \.element.id) { index, finding in
                        HStack(alignment: .top, spacing: Space.sm) {
                            StatusDot(level: finding.status.badgeLevel, size: 6).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(finding.title).font(Typo.captionStrong).lineLimit(1)
                                Text(finding.detail).font(Typo.caption).foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        if index < result.findings.count - 1 {
                            Rectangle().fill(Surface.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var historyCard: some View {
        let store = AuditHistoryStore.shared
        return Card(title: T("记录", "History"), icon: "clock.arrow.circlepath") {
            if store.results.isEmpty {
                Text(T("暂无记录", "No records")).font(Typo.caption).foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.results.prefix(8).enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: Space.sm) {
                            Text("\(item.score)")
                                .font(Typo.captionStrong)
                                .foregroundColor(ScorePalette.color(item.score))
                                .frame(width: 26, alignment: .leading)
                            Text(item.verdict).font(Typo.caption)
                            Spacer()
                            Text(Format.dateTime(item.date))
                                .font(Typo.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: Metrics.row)
                        if index < min(store.results.count, 8) - 1 {
                            Rectangle().fill(Surface.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}
