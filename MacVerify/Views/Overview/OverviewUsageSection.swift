// Views/Overview/OverviewUsageSection.swift
//
// 使用强度：崩溃记录、SSD 磨损、累计写入。只在有数据时出现。
// 改造前是三个裸数字挂在一张高卡里，右侧空着；现在用紧凑指标块横向铺开。
import SwiftUI

struct OverviewUsageSection: View {
    let info: MacSystemInfo

    private var hasContent: Bool {
        info.panicLogCount > 0
            || info.storage.smartPercentageUsed != nil
            || info.storage.statisticsAvailable
    }

    var body: some View {
        if hasContent {
            Card(title: T("使用强度", "Usage"), icon: "gauge.medium") {
                HStack(spacing: Space.sm) {
                    if info.panicLogCount > 0 {
                        StatTile(title: T("崩溃日志", "Panic logs"),
                                 value: "\(info.panicLogCount)",
                                 detail: info.lastPanicDate.map { Format.dateTime($0) },
                                 color: StatusPalette.warning,
                                 icon: "exclamationmark.triangle")
                    }
                    if let smartUsed = info.storage.smartPercentageUsed {
                        StatTile(title: T("SSD 已用寿命", "SSD wear"),
                                 value: "\(smartUsed)", unit: "%",
                                 color: smartUsed > 50 ? StatusPalette.warning : .secondary,
                                 icon: "internaldrive")
                    }
                    if info.storage.statisticsAvailable {
                        StatTile(title: T("累计写入", "Total written"),
                                 value: Format.bytes(info.storage.writtenBytes),
                                 detail: T("卷级统计，格式化后清零", "Volume level; resets on erase"),
                                 color: .secondary,
                                 icon: "arrow.down.doc")
                    }
                }
            }
        }
    }
}
