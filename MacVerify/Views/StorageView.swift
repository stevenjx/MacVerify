// Views/StorageView.swift
//
// 存储页重排为「磁盘 / 健康」并排，明细三列铺开。
// 改造前所有内容塞在一张卡里，区块标题还因为 VStack 默认居中而飘在中间。
import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var system: SystemInfoStore
    @StateObject private var benchmark = DiskBenchmark()
    @State private var selectedSize = 1024

    private var storage: StorageInfo { system.info.storage }
    private let sizes = [512, 1024, 2048]

    private var driveFacts: [Fact] {
        var facts: [Fact] = [
            Fact(T("磁盘型号", "Drive model"), storage.deviceName),
            Fact(T("标称容量", "Marketing"), storage.marketingCapacity),
            Fact(T("物理容量", "Physical"),
                 storage.physicalBytes > 0
                    ? "\(Format.bytes(storage.physicalBytes)) · \(storage.physicalBytes) B"
                    : T("不可用", "Unavailable"),
                 mono: true,
                 state: storage.physicalBytes > 0 ? .normal : .unavailable),
            Fact(T("卷容量", "Volume"), volumeCapacityText)
        ]
        if let used = storage.smartPercentageUsed {
            facts.append(Fact(T("寿命消耗", "Wear used"), "\(used)%",
                              color: used >= 50 ? StatusPalette.warning : .primary))
        }
        if let spare = storage.smartAvailableSpare {
            let threshold = storage.smartSpareThreshold.map { T(" · 阈值 \($0)%", " · threshold \($0)%") } ?? ""
            facts.append(Fact(T("剩余备用块", "Available spare"), "\(spare)%\(threshold)"))
        }
        return facts
    }

    private var detailFacts: [Fact] {
        var facts: [Fact] = []
        if let hours = storage.smartPowerOnHours {
            facts.append(Fact(T("上电时长", "Power-on hours"), "\(hours) h"))
        }
        if let cycles = storage.smartPowerCycles {
            facts.append(Fact(T("上电次数", "Power cycles"), "\(cycles)"))
        }
        if let shutdowns = storage.smartUnsafeShutdowns {
            facts.append(Fact(T("异常断电", "Unsafe shutdowns"), "\(shutdowns)",
                              color: shutdowns > 100 ? StatusPalette.warning : .primary))
        }
        if let errors = storage.smartMediaErrors {
            facts.append(Fact(T("介质错误", "Media errors"), "\(errors)",
                              color: errors > 0 ? StatusPalette.critical : .primary))
        }
        if let entries = storage.smartErrorLogEntries {
            facts.append(Fact(T("错误日志条目", "Error log entries"), "\(entries)"))
        }
        if let temperature = storage.smartTemperature {
            facts.append(Fact(T("SSD 温度", "SSD temperature"), String(format: "%.1f °C", temperature)))
        }
        if let read = storage.smartLifetimeReadBytes {
            facts.append(Fact(T("SSD 累计读取", "SSD lifetime read"), Format.bytes(read)))
        } else {
            facts.append(Fact(T("SSD 累计读取", "SSD lifetime read"), T("不可用", "Unavailable"),
                              state: .unavailable))
        }
        if let written = storage.smartLifetimeWrittenBytes {
            facts.append(Fact(T("SSD 累计写入", "SSD lifetime written"), Format.bytes(written)))
        } else {
            facts.append(Fact(T("SSD 累计写入", "SSD lifetime written"), T("不可用", "Unavailable"),
                              state: .unavailable))
        }
        facts.append(Fact(T("卷级读取", "Volume read"),
                          storage.statisticsAvailable ? Format.bytes(storage.readBytes) : T("不可用", "Unavailable"),
                          state: storage.statisticsAvailable ? .normal : .unavailable))
        facts.append(Fact(T("卷级写入", "Volume write"),
                          storage.statisticsAvailable ? Format.bytes(storage.writtenBytes) : T("不可用", "Unavailable"),
                          state: storage.statisticsAvailable ? .normal : .unavailable))
        if let commands = storage.smartHostWriteCommands {
            facts.append(Fact(T("写入命令数", "Host write commands"), Format.count(commands)))
        }
        return facts
    }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("存储", "Storage"),
                subtitle: T("容量、SMART 状态与顺序读写测试", "Capacity, SMART status and sequential throughput")
            )

            HStack(alignment: .top, spacing: Metrics.pageGap) {
                Card(title: T("磁盘", "Drive"), icon: "internaldrive",
                     trailing: AnyView(
                        Text(storage.isInternalDisk == false
                             ? T("外接启动盘", "External boot disk")
                             : T("内置", "Internal"))
                            .font(Typo.caption)
                            .foregroundColor(.secondary)
                     )) {
                    FactGrid(facts: driveFacts, columns: 1)
                }
                .frame(width: 380)

                Card(title: T("SMART 健康", "SMART health"), icon: "heart.text.square") {
                    HStack(alignment: .center, spacing: Space.xl) {
                        if let health = storage.smartHealthPercent {
                            RingGauge(title: T("剩余寿命", "Life remaining"),
                                      value: Double(health),
                                      color: health >= 80 ? StatusPalette.ok
                                           : (health >= 50 ? StatusPalette.warning : StatusPalette.critical),
                                      size: 84)
                        } else {
                            VStack(spacing: Space.xs) {
                                Image(systemName: "minus.circle")
                                    .font(Typo.icon(20, weight: .light))
                                    .foregroundColor(.secondary)
                                Text(T("无 SMART", "No SMART"))
                                    .font(Typo.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 84, height: 84)
                        }

                        VStack(spacing: Space.sm) {
                            HStack(spacing: Space.sm) {
                                StatTile(title: T("SMART 状态", "SMART status"),
                                         value: smartShortText,
                                         color: smartColor, icon: "checkmark.shield")
                                StatTile(title: T("上电时长", "Power-on"),
                                         value: storage.smartPowerOnHours.map { "\($0)" } ?? "—",
                                         unit: storage.smartPowerOnHours == nil ? nil : "h",
                                         color: .secondary)
                            }
                            HStack(spacing: Space.sm) {
                                StatTile(title: T("异常断电", "Unsafe shutdown"),
                                         value: storage.smartUnsafeShutdowns.map { "\($0)" } ?? "—",
                                 placeholder: storage.smartUnsafeShutdowns == nil,
                                         color: (storage.smartUnsafeShutdowns ?? 0) > 100 ? StatusPalette.warning : .secondary)
                                StatTile(title: T("SSD 温度", "Temperature"),
                                         value: storage.smartTemperature.map { String(format: "%.1f", $0) } ?? "—",
                                         unit: storage.smartTemperature == nil ? nil : "°C",
                                         color: .secondary)
                            }
                        }
                    }
                }
            }

            Card(title: T("SMART 明细", "SMART details"), icon: "list.bullet.rectangle",
                 trailing: AnyView(
                    Text(storage.smartSource ?? "")
                        .font(Typo.mono)
                        .foregroundColor(.secondary)
                 )) {
                FactGrid(facts: detailFacts, columns: 3)
            }

            Card(title: T("顺序读写测试", "Sequential benchmark"), icon: "speedometer",
                 trailing: AnyView(
                    HStack(spacing: Space.sm) {
                        SegmentedPicker(options: sizes,
                                        title: { $0 >= 1024 ? "\($0 / 1024) GB" : "\($0) MB" },
                                        selection: $selectedSize,
                                        enabled: !benchmark.isRunning)
                        if benchmark.isRunning {
                            SecondaryButton(title: T("停止", "Stop"), icon: "stop.fill") { benchmark.cancel() }
                        } else {
                            PrimaryButton(title: T("开始测试", "Run test"), icon: "play.fill",
                                          enabled: storage.physicalBytes > 0) {
                                benchmark.start(sizeMB: selectedSize)
                            }
                        }
                    }
                 )) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: Space.sm) {
                        StatTile(title: T("写入", "Write"),
                                 value: benchmark.writeSpeed > 0 ? Format.speed(benchmark.writeSpeed) : "—",
                                 placeholder: benchmark.writeSpeed <= 0,
                                 detail: T("含落盘同步", "Including flush"),
                                 color: StatusPalette.warning, icon: "arrow.down.doc")
                        StatTile(title: T("读取", "Read"),
                                 value: benchmark.readSpeed > 0 ? Format.speed(benchmark.readSpeed) : "—",
                                 placeholder: benchmark.readSpeed <= 0,
                                 detail: T("绕过页缓存", "Bypassing page cache"),
                                 color: StatusPalette.ok, icon: "arrow.up.doc")
                    }

                    if benchmark.isRunning || benchmark.progress > 0 {
                        ProgressView(value: benchmark.progress)
                            .progressViewStyle(.linear)
                    }

                    Text(benchmark.message)
                        .font(Typo.caption)
                        .foregroundColor(.secondary)

                    Text(T("测试会在临时目录写入随机数据并立即落盘，结束后自动删除。SSD 写入速度会随剩余空间下降，建议空间充足时测试。",
                           "The test writes random data to the temporary directory, flushes it, then deletes it. SSD write speed drops as free space shrinks."))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !storage.smartAvailable {
                NoticeBar(
                    text: T("本机未返回 SMART 数据。常见原因：外接盘通过 USB 桥接（不转发 SMART）、或系统版本过旧。内置 SSD 在 macOS 12 及以上通常可读。",
                           "No SMART data returned. Common causes: a USB-bridged external drive, or an old macOS. Built-in SSDs are usually readable on macOS 12 and later."),
                    level: .neutral
                )
            }
        }
        .onDisappear {
            if benchmark.isRunning { benchmark.cancel() }
        }
    }

    /// 指标块里只放短词，完整措辞放在工厂行的「SMART 状态」里
    private var smartShortText: String {
        guard let health = storage.smartHealthPercent else {
            return storage.smartStatusText ?? T("不可用", "Unavailable")
        }
        return health >= 80 ? T("正常", "OK") : T("\(health)%", "\(health)%")
    }

    private var smartColor: Color {
        guard let health = storage.smartHealthPercent else { return .secondary }
        return health >= 80 ? StatusPalette.ok : (health >= 50 ? StatusPalette.warning : StatusPalette.critical)
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
}
