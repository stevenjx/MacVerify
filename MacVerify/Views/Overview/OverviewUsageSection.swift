// Views/Overview/OverviewUsageSection.swift
//
// 使用强度：崩溃记录、SSD 磨损、累计写入。只在有数据时出现。
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
            Card {
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionHeader(title: T("使用强度", "USAGE"))
                    HStack(alignment: .top, spacing: Space.xl) {
                        if info.panicLogCount > 0 {
                            metric(T("崩溃日志", "Panic logs"), "\(info.panicLogCount)", color: .primary) {
                                if let date = info.lastPanicDate {
                                    Text(Format.dateTime(date))
                                        .font(Typo.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        if let smartUsed = info.storage.smartPercentageUsed {
                            metric(T("SSD 已用寿命", "SSD wear"), "\(smartUsed)%",
                                   color: smartUsed > 50 ? StatusPalette.warning : .primary)
                        }
                        if info.storage.statisticsAvailable {
                            metric(T("累计写入", "Total written"), Format.bytes(info.storage.writtenBytes), color: .primary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func metric<Detail: View>(_ title: String, _ value: String, color: Color,
                                      @ViewBuilder detail: () -> Detail = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Typo.caption).foregroundColor(.secondary)
            Text(value).font(Typo.metric).foregroundColor(color)
            detail()
        }
    }
}
