// Views/Overview/OverviewHero.swift
//
// 概览页顶部：机型图 + 三个环形仪表。
// 环里的数字全部是本机真实读数（电池健康度、SSD 健康度、电池循环），
// 取不到时环留空、环心显示「—」，不用 0 或估算值顶替。
import SwiftUI

struct OverviewHero: View {
    let info: MacSystemInfo
    let battery: BatterySnapshot

    private let tileHeight: CGFloat = 150

    var body: some View {
        HStack(spacing: Metrics.pageGap) {
            artwork

            tile {
                RingGauge(
                    title: T("电池健康度", "Battery health"),
                    value: batteryHealth ?? 0,
                    unit: "%",
                    color: healthColor,
                    caption: healthCaption,
                    size: 92,
                    centerText: batteryHealth == nil ? "—" : nil
                )
            }

            tile {
                RingGauge(
                    title: T("SSD 健康度", "SSD health"),
                    value: Double(info.storage.smartHealthPercent ?? 0),
                    unit: "%",
                    color: ssdColor,
                    caption: wearCaption,
                    size: 92,
                    centerText: info.storage.smartHealthPercent == nil ? "—" : nil
                )
            }

            tile {
                RingGauge(
                    title: T("电池循环", "Battery cycles"),
                    value: cycleValue,
                    total: cycleLimit,
                    unit: "",
                    color: cycleColor,
                    caption: cycleLimitCaption,
                    size: 92,
                    centerText: cycleCenter
                )
            }
        }
    }

    // MARK: - 机型图

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Surface.well)

            if let imageName = MacModelCatalog.imageName(for: info.modelIdentifier) {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(Space.md)
            } else {
                VStack(spacing: Space.xs) {
                    Image(systemName: "laptopcomputer")
                        .font(Typo.icon(30, weight: .light))
                        .foregroundColor(.secondary)
                    Text(T("未收录的机型", "Unlisted model"))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 226, height: tileHeight)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Surface.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(T("机型示意图", "Model artwork"))
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Surface.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Surface.border, lineWidth: 1)
            )
    }

    // MARK: - 电池健康度

    private var batteryHealth: Double? {
        battery.isPresent ? battery.healthPercent : nil
    }

    private var healthColor: Color {
        switch battery.healthGrade {
        case .excellent, .good: return StatusPalette.ok
        case .fair: return StatusPalette.warning
        case .service: return StatusPalette.critical
        case .unknown: return StatusPalette.neutral
        }
    }

    private var healthCaption: String? {
        guard battery.isPresent else { return T("未检测到电池", "No battery detected") }
        guard battery.cycleCountAvailable else { return nil }
        return T("\(battery.cycleCount) 次循环", "\(battery.cycleCount) cycles")
    }

    // MARK: - SSD 健康度

    /// 与存储页同一口径：≥80 正常，≥50 需留意，其余告警。
    private var ssdColor: Color {
        guard let health = info.storage.smartHealthPercent else { return StatusPalette.neutral }
        if health >= 80 { return StatusPalette.ok }
        if health >= 50 { return StatusPalette.warning }
        return StatusPalette.critical
    }

    private var wearCaption: String? {
        if let used = info.storage.smartPercentageUsed {
            return T("\(used)% 寿命已用", "\(used)% life used")
        }
        return info.storage.smartAvailable ? nil : T("无 SMART 数据", "No SMART data")
    }

    // MARK: - 电池循环

    private var cycleValue: Double {
        battery.cycleCountAvailable ? Double(battery.cycleCount) : 0
    }

    /// 设计循环上限。机型不提供时按 1000 次画刻度，但下方注明「未知」，不声称这是官方值。
    private var cycleLimit: Double {
        guard battery.designCycleCountAvailable, battery.designCycleCount > 0 else { return 1000 }
        return Double(battery.designCycleCount)
    }

    private var cycleRatio: Double {
        cycleLimit > 0 ? cycleValue / cycleLimit : 0
    }

    private var cycleColor: Color {
        guard battery.cycleCountAvailable else { return StatusPalette.neutral }
        if cycleRatio <= 0.5 { return StatusPalette.ok }
        if cycleRatio <= 0.8 { return StatusPalette.warning }
        return StatusPalette.critical
    }

    private var cycleCenter: String {
        battery.cycleCountAvailable ? String(battery.cycleCount) : "—"
    }

    private var cycleLimitCaption: String {
        guard battery.isPresent else { return T("未检测到电池", "No battery detected") }
        guard battery.designCycleCountAvailable, battery.designCycleCount > 0 else {
            return T("设计上限未知", "Rated limit unknown")
        }
        return T("设计上限 \(battery.designCycleCount) 次", "Rated \(battery.designCycleCount) cycles")
    }
}
