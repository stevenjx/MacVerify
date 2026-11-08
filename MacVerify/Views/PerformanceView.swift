// Views/PerformanceView.swift
import SwiftUI

struct PerformanceView: View {
    @EnvironmentObject private var system: SystemInfoStore
    @EnvironmentObject private var battery: BatteryStore

    @StateObject private var cpuBenchmark = CPUBenchmark()
    @StateObject private var gpuBenchmark = GPUBenchmark()
    @State private var gpuDuration = 30
    @State private var cpuRuns: [CPURun] = []

    /// 一次 CPU 测试的结果。只存本次会话，不落盘：用于观察持续压测下的衰减。
    private struct CPURun: Identifiable {
        let id = UUID()
        let index: Int
        let single: Double
        let multi: Double
    }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("性能测试", "Benchmarks"),
                subtitle: T("处理器算力与图形负载，用于验证散热与稳定性", "CPU throughput and GPU load to verify thermals and stability")
            )

            cpuCard
            if cpuRuns.count >= 2 { runsCard }
            gpuCard

            NoticeBar(
                text: T("压测会让风扇满载、机身发热，属于正常现象。测试期间请保持电源连接，结束后关闭测试即可让温度回落。",
                       "Stress tests spin up the fans and heat the chassis — that is expected. Keep the Mac on power and stop the test to let it cool down."),
                level: .neutral
            )
        }
        .onChange(of: cpuBenchmark.isRunning) { running in
            guard !running, cpuBenchmark.multiCoreMops > 0 else { return }
            cpuRuns.append(CPURun(index: cpuRuns.count + 1,
                                  single: cpuBenchmark.singleCoreMops,
                                  multi: cpuBenchmark.multiCoreMops))
        }
        .onDisappear {
            gpuBenchmark.cancel()
        }
    }

    // MARK: - CPU

    private var cpuCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: T("处理器", "PROCESSOR"))
                    Spacer()
                    if cpuBenchmark.isRunning {
                        SecondaryButton(title: T("测试中…", "Running…"), enabled: false) {}
                    } else {
                        PrimaryButton(title: T("开始测试", "Run test"), icon: "play.fill") {
                            cpuBenchmark.start()
                        }
                    }
                }

                HStack(spacing: 12) {
                    StatTile(title: T("单核吞吐", "Single-core"),
                             value: cpuBenchmark.singleCoreMops > 0 ? String(format: "%.0f Mops/s", cpuBenchmark.singleCoreMops) : "—",
                             detail: system.info.chipName,
                             color: .accentColor, icon: "cpu")
                    StatTile(title: T("多核吞吐", "Multi-core"),
                             value: cpuBenchmark.multiCoreMops > 0 ? String(format: "%.0f Mops/s", cpuBenchmark.multiCoreMops) : "—",
                             detail: T("\(system.info.logicalCores) 线程", "\(system.info.logicalCores) threads"),
                             color: SeriesPalette.cpuMulti, icon: "cpu")
                    if let temperature = battery.battery.temperature {
                        StatTile(title: T("电池温度", "Battery temp"),
                                 value: String(format: "%.1f °C", temperature),
                                 detail: T("来自电池管理芯片", "From the battery gauge"),
                                 color: temperature > 40 ? StatusPalette.warning : StatusPalette.ok, icon: "thermometer")
                    }
                }

                if cpuBenchmark.isRunning {
                    ProgressView(value: cpuBenchmark.progress).progressViewStyle(.linear)
                }
                Text(cpuBenchmark.message).font(Typo.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 本轮多次测试

    /// 多次测试的横向对比。以本轮最高值为 100%，看的是「同一台机器在自己前后几次里的变化」，
    /// 不与任何外部机型基准比较——那种表会过期，写错就是新的假数据。
    private var runsCard: some View {
        let best = cpuRuns.map(\.multi).max() ?? 1
        let rows = cpuRuns.map { run in
            BarRow(label: T("第 \(run.index) 次", "Run \(run.index)"),
                   value: run.multi,
                   valueText: String(format: "%.0f", run.multi),
                   color: SeriesPalette.cpuMulti)
        }
        let worst = cpuRuns.map(\.multi).min() ?? best
        let drop = best > 0 ? (best - worst) / best * 100 : 0

        return Card {
            VStack(alignment: .leading, spacing: Space.sm + 2) {
                HStack {
                    SectionHeader(title: T("本轮多次测试", "THIS SESSION"), icon: "chart.bar")
                    Spacer()
                    if drop > 5 {
                        StatusBadge(text: T("最大衰减 \(String(format: "%.0f", drop))%", "\(String(format: "%.0f", drop))% drop"), level: .warning)
                    } else {
                        StatusBadge(text: T("波动正常", "Stable"), level: .ok)
                    }
                }
                HorizontalBars(rows: rows)
                Text(T("多核吞吐，以本轮最高一次为 100%。持续压测下明显下滑通常意味着散热受限。",
                       "Multi-core throughput, with the best run of this session as 100%. A clear decline under sustained load usually means thermal throttling."))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - GPU

    private var gpuCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: T("图形处理器", "GRAPHICS"))
                    Spacer()
                    if gpuBenchmark.isRunning {
                        SecondaryButton(title: T("停止", "Stop"), icon: "stop.fill") { gpuBenchmark.cancel() }
                    } else {
                        PrimaryButton(title: T("开始压测", "Run stress test"), icon: "play.fill", enabled: gpuBenchmark.supportsMetal) {
                            gpuBenchmark.start(seconds: gpuDuration)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text(gpuBenchmark.gpuName).font(Typo.caption)
                    if !gpuBenchmark.supportsMetal {
                        StatusBadge(text: T("不支持 Metal", "Metal unavailable"), level: .critical)
                    }
                    Spacer()
                    ForEach([30, 60, 120], id: \.self) { seconds in
                        Button(action: { gpuDuration = seconds }) {
                            Text("\(seconds)s")
                                .font(Typo.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(gpuDuration == seconds ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                                .foregroundColor(gpuDuration == seconds ? .accentColor : .primary)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .disabled(gpuBenchmark.isRunning)
                    }
                }

                HStack(spacing: 12) {
                    StatTile(title: T("实时批次/秒", "Batches/s"),
                             value: gpuBenchmark.isRunning ? String(format: "%.0f", gpuBenchmark.framesPerSecond) : "—",
                             detail: T("Metal 计算管线提交完成数", "Completed Metal compute batches"),
                             color: SeriesPalette.gpuLive, icon: "square.stack.3d.up")
                    StatTile(title: T("峰值", "Peak"),
                             value: gpuBenchmark.peakFramesPerSecond > 0 ? String(format: "%.0f", gpuBenchmark.peakFramesPerSecond) : "—",
                             detail: T("本次测试最高值", "Highest this run"),
                             color: SeriesPalette.gpuPeak, icon: "arrow.up.right")
                    StatTile(title: T("已运行", "Elapsed"),
                             value: String(format: "%.0f s", gpuBenchmark.elapsed),
                             detail: T("批次数 \(gpuBenchmark.completedBatches)", "\(gpuBenchmark.completedBatches) batches"),
                             color: .secondary, icon: "clock")
                }

                if gpuBenchmark.isRunning {
                    ProgressView(value: gpuBenchmark.progress).progressViewStyle(.linear)
                }
                Text(gpuBenchmark.message).font(Typo.caption).foregroundColor(.secondary)
            }
        }
    }
}
