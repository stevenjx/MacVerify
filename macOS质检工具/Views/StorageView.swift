// Views/StorageView.swift
import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var system: SystemInfoStore
    @StateObject private var benchmark = DiskBenchmark()
    @State private var selectedSize = 1024

    private var storage: StorageInfo { system.info.storage }
    private let sizes = [512, 1024, 2048]

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("存储", "Storage"),
                subtitle: T("容量、SMART 状态与顺序读写测试", "Capacity, SMART status and sequential throughput")
            )

            Card {
                VStack(spacing: 0) {
                    SectionHeader(title: T("磁盘", "DRIVE")).padding(.bottom, 8)
                    InfoRow(label: T("磁盘型号", "Drive model"), value: storage.deviceName)
                    InfoRow(label: T("卷容量", "Volume capacity"), value: "\(system.info.storage.totalGB) GB")
                    InfoRow(label: T("SMART 状态", "SMART status"), value: smartText, valueColor: smartColor)
                    if let used = storage.smartPercentageUsed {
                        InfoRow(label: T("寿命消耗", "Wear used"), value: "\(used)%")
                    }
                    if let spare = storage.smartAvailableSpare {
                        InfoRow(label: T("剩余备用块", "Available spare"), value: "\(spare)%")
                    }
                    InfoRow(label: T("累计读取", "Total read"), value: storage.statisticsAvailable ? Format.bytes(storage.readBytes) : T("不可用", "Unavailable"))
                    InfoRow(label: T("累计写入", "Total written"), value: storage.statisticsAvailable ? Format.bytes(storage.writtenBytes) : T("不可用", "Unavailable"), isLast: true)

                    if !storage.smartAvailable {
                        NoticeBar(
                            text: T("该机型未向用户态公开 SMART 数据。Apple Silicon 机型通常在系统内部读取，第三方工具无法获取，这是系统限制而非故障。",
                                   "SMART data is not exposed on this model. Apple Silicon Macs read it internally; third-party tools cannot. This is a system limitation, not a fault."),
                            level: .neutral
                        )
                        .padding(.top, 10)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: T("顺序读写测试", "SEQUENTIAL BENCHMARK"))

                    HStack(spacing: 10) {
                        Text(T("测试文件大小", "Test size")).font(.system(size: 11)).foregroundColor(.secondary)
                        ForEach(sizes, id: \.self) { size in
                            Button(action: { selectedSize = size }) {
                                Text(size >= 1024 ? "\(size / 1024) GB" : "\(size) MB")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selectedSize == size ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                                    .foregroundColor(selectedSize == size ? .accentColor : .primary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(benchmark.isRunning)
                        }
                        Spacer()
                        if benchmark.isRunning {
                            SecondaryButton(title: T("停止", "Stop"), icon: "stop.fill") { benchmark.cancel() }
                        } else {
                            PrimaryButton(title: T("开始测试", "Run test"), icon: "play.fill", enabled: system.info.storage.totalGB > 0) {
                                benchmark.start(sizeMB: selectedSize)
                            }
                        }
                    }

                    if benchmark.isRunning || benchmark.progress > 0 {
                        ProgressView(value: benchmark.progress)
                            .progressViewStyle(.linear)
                    }

                    Text(benchmark.message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        StatTile(title: T("写入", "Write"),
                                 value: benchmark.writeSpeed > 0 ? Format.speed(benchmark.writeSpeed) : "—",
                                 detail: T("含落盘同步", "Including flush"),
                                 color: .orange, icon: "arrow.down.doc")
                        StatTile(title: T("读取", "Read"),
                                 value: benchmark.readSpeed > 0 ? Format.speed(benchmark.readSpeed) : "—",
                                 detail: T("绕过页缓存", "Bypassing page cache"),
                                 color: .green, icon: "arrow.up.doc")
                    }

                    Text(T("测试会在临时目录写入随机数据并立即落盘，结束后自动删除。固态硬盘的写入速度会随剩余空间下降，建议在可用空间充足时测试。",
                           "The test writes random data to the temporary directory and flushes it, then deletes the file. SSD write speed drops as free space shrinks — test with plenty of free space."))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var smartText: String {
        if let health = storage.smartHealthPercent {
            return health >= 80 ? T("正常（\(health)%）", "OK (\(health)%)") : T("剩余 \(health)%", "\(health)% remaining")
        }
        return T("不可用", "Unavailable")
    }

    private var smartColor: Color {
        guard let health = storage.smartHealthPercent else { return .secondary }
        return health >= 80 ? .primary : (health >= 50 ? .orange : .red)
    }
}
