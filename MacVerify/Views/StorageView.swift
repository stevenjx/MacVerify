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
                    InfoRow(label: T("标称容量", "Marketing capacity"),
                            value: storage.marketingCapacity == "—" ? "—" : storage.marketingCapacity)
                    InfoRow(label: T("物理容量", "Physical capacity"),
                            value: storage.physicalBytes > 0
                                ? "\(Format.bytes(storage.physicalBytes))（\(storage.physicalBytes) B）"
                                : T("不可用", "Unavailable"))
                    InfoRow(label: T("可用卷容量", "Volume capacity"),
                            value: volumeCapacityText)

                    SectionHeader(title: T("SMART", "SMART"))
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                    InfoRow(label: T("SMART 状态", "SMART status"), value: smartText, valueColor: smartColor)
                    if let used = storage.smartPercentageUsed {
                        InfoRow(label: T("寿命消耗", "Wear used"), value: "\(used)%")
                    }
                    if let spare = storage.smartAvailableSpare {
                        let threshold = storage.smartSpareThreshold.map { T(" · 阈值 \($0)%", " · threshold \($0)%") } ?? ""
                        InfoRow(label: T("剩余备用块", "Available spare"), value: "\(spare)%\(threshold)")
                    }

                    SectionHeader(title: T("累计读写", "CUMULATIVE I/O"))
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                    InfoRow(label: T("SSD 累计读取", "SSD lifetime read"), value: lifetimeReadText)
                    InfoRow(label: T("SSD 累计写入", "SSD lifetime written"), value: lifetimeWriteText)
                    InfoRow(label: T("卷级读取", "Volume read"),
                            value: storage.statisticsAvailable ? Format.bytes(storage.readBytes) : T("不可用", "Unavailable"))
                    InfoRow(label: T("卷级写入", "Volume write"),
                            value: storage.statisticsAvailable ? Format.bytes(storage.writtenBytes) : T("不可用", "Unavailable"))

                    if storage.smartAvailable {
                        SectionHeader(title: T("SMART 明细", "SMART DETAILS"))
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                        if let hours = storage.smartPowerOnHours {
                            InfoRow(label: T("上电时长", "Power-on hours"), value: "\(hours) h")
                        }
                        if let cycles = storage.smartPowerCycles {
                            InfoRow(label: T("上电次数", "Power cycles"), value: "\(cycles)")
                        }
                        if let shutdowns = storage.smartUnsafeShutdowns {
                            InfoRow(label: T("异常断电", "Unsafe shutdowns"),
                                    value: "\(shutdowns)",
                                    valueColor: shutdowns > 100 ? StatusPalette.warning : .primary)
                        }
                        if let errors = storage.smartMediaErrors {
                            InfoRow(label: T("介质错误", "Media errors"),
                                    value: "\(errors)",
                                    valueColor: errors > 0 ? StatusPalette.critical : .primary)
                        }
                        if let entries = storage.smartErrorLogEntries {
                            InfoRow(label: T("错误日志条目", "Error log entries"), value: "\(entries)")
                        }
                        if let temperature = storage.smartTemperature {
                            InfoRow(label: T("SSD 温度", "SSD temperature"),
                                    value: String(format: "%.1f °C", temperature))
                        }
                        if let commands = storage.smartHostWriteCommands {
                            InfoRow(label: T("写入命令数", "Host write commands"), value: Format.count(commands))
                        }
                        if let source = storage.smartSource {
                            Text(T("数据来源：\(source)", "Source: \(source)"))
                                .font(Typo.mono)
                                .foregroundColor(.secondary.opacity(0.8))
                                .padding(.top, 6)
                        }
                    }

                    if !storage.smartAvailable {
                        NoticeBar(
                            text: T("本机未返回 SMART 数据。常见原因：外接盘通过 USB 桥接（不转发 SMART）、或系统版本过旧。内置 SSD 在 macOS 12 及以上通常可读。",
                                   "No SMART data returned. Common causes: a USB-bridged external drive (which does not forward SMART), or an old macOS. Built-in SSDs are usually readable on macOS 12 and later."),
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
                        Text(T("测试文件大小", "Test size")).font(Typo.caption).foregroundColor(.secondary)
                        ForEach(sizes, id: \.self) { size in
                            Button(action: { selectedSize = size }) {
                                Text(size >= 1024 ? "\(size / 1024) GB" : "\(size) MB")
                                    .font(Typo.caption)
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
                            PrimaryButton(title: T("开始测试", "Run test"), icon: "play.fill", enabled: system.info.storage.physicalBytes > 0) {
                                benchmark.start(sizeMB: selectedSize)
                            }
                        }
                    }

                    if benchmark.isRunning || benchmark.progress > 0 {
                        ProgressView(value: benchmark.progress)
                            .progressViewStyle(.linear)
                    }

                    Text(benchmark.message)
                        .font(Typo.mono)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        StatTile(title: T("写入", "Write"),
                                 value: benchmark.writeSpeed > 0 ? Format.speed(benchmark.writeSpeed) : "—",
                                 detail: T("含落盘同步", "Including flush"),
                                 color: StatusPalette.warning, icon: "arrow.down.doc")
                        StatTile(title: T("读取", "Read"),
                                 value: benchmark.readSpeed > 0 ? Format.speed(benchmark.readSpeed) : "—",
                                 detail: T("绕过页缓存", "Bypassing page cache"),
                                 color: StatusPalette.ok, icon: "arrow.up.doc")
                    }

                    Text(T("测试会在临时目录写入随机数据并立即落盘，结束后自动删除。固态硬盘的写入速度会随剩余空间下降，建议在可用空间充足时测试。",
                           "The test writes random data to the temporary directory and flushes it, then deletes the file. SSD write speed drops as free space shrinks — test with plenty of free space."))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onDisappear {
            if benchmark.isRunning { benchmark.cancel() }
        }
    }

    private var smartText: String {
        if let health = storage.smartHealthPercent {
            return health >= 80 ? T("正常（\(health)%）", "OK (\(health)%)") : T("剩余 \(health)%", "\(health)% remaining")
        }
        if let status = storage.smartStatusText { return status }
        return T("不可用", "Unavailable")
    }

    /// 全生命周期累计读取（NVMe SMART），与"卷级统计"不同：格式化不会清零。
    private var lifetimeReadText: String {
        guard let bytes = storage.smartLifetimeReadBytes else { return T("不可用", "Unavailable") }
        return Format.bytes(bytes)
    }

    private var lifetimeWriteText: String {
        guard let bytes = storage.smartLifetimeWrittenBytes else { return T("不可用", "Unavailable") }
        return Format.bytes(bytes)
    }

    /// 根卷所在 APFS 容器的可用容量。与物理容量区分，避免把 1TB 机器读成 995GB。
    private var volumeCapacityText: String {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity else {
            return T("不可用", "Unavailable")
        }
        let totalText = Format.bytes(UInt64(total))
        if let free = values.volumeAvailableCapacity {
            return T("\(totalText)（可用 \(Format.bytes(UInt64(free)))）",
                     "\(totalText) (\(Format.bytes(UInt64(free))) free)")
        }
        return totalText
    }

    private var smartColor: Color {
        guard let health = storage.smartHealthPercent else { return .secondary }
        return health >= 80 ? .primary : (health >= 50 ? StatusPalette.warning : StatusPalette.critical)
    }
}
