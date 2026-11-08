// Views/Overview/OverviewAuditCards.swift
//
// 一致性核验 + 原装性核对。两张卡结构相同，共用一个行渲染器，
// 改造前是两段几乎一样的复制粘贴（各 40 行）。
import SwiftUI

/// 把两种不同的 finding 类型归一成一种可渲染的行
struct AuditRow: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let level: BadgeLevel
}

struct OverviewAuditCards: View {
    let info: MacSystemInfo
    let battery: BatterySnapshot

    var body: some View {
        let consistency = ConsistencyAudit.run(info: info)
        let originality = OriginalityCheck.run(info: info, battery: battery)

        VStack(spacing: Space.lg) {
            card(
                title: T("一致性核验", "CONSISTENCY"),
                explanation: T("同一项事实分别从系统报告与内核接口读取，两路结果必须一致。改机型、刷序列号会在这里暴露。",
                               "Each fact is read from two independent sources — the system report and the kernel interface. Tampered model or serial data shows up here."),
                rows: consistency.map {
                    AuditRow(title: $0.title, detail: $0.detail, level: $0.state.badgeLevel)
                },
                badge: badge(
                    risks: consistency.filter { $0.state == .inconsistent }.count,
                    notices: consistency.filter { $0.state == .notice }.count,
                    okText: T("全部一致", "All consistent"),
                    noticeText: { T("\($0) 项需确认", "\($0) to confirm") },
                    riskText: { T("\($0) 项不一致", "\($0) mismatch(es)") }
                ),
                footer: nil
            )

            card(
                title: T("原装性核对", "ORIGINALITY"),
                explanation: T("屏幕、内存、存储、电池规格与 Apple 官方技术规格比对。不匹配只代表「与官方规格不符」，不代表一定被改装过——维修换板也会造成同样结果。",
                               "Display, memory, storage and battery are compared against Apple's published tech specs. A mismatch means \"not matching Apple's spec\", not proof of modification — a board-level repair would look the same."),
                rows: originality.map {
                    AuditRow(title: $0.title, detail: $0.detail, level: $0.state.badgeLevel)
                },
                badge: originalityBadge(originality),
                footer: baselineText
            )
        }
    }

    // MARK: - 局部

    private func card(title: String, explanation: String, rows: [AuditRow],
                      badge: (text: String, level: BadgeLevel), footer: String?) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm + 2) {
                HStack {
                    SectionHeader(title: title)
                    Spacer()
                    StatusBadge(text: badge.text, level: badge.level)
                }

                Text(explanation)
                    .font(Typo.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: Space.sm) {
                        Image(systemName: row.level.symbol)
                            .font(Typo.icon(11))
                            .foregroundColor(row.level.color)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title).font(Typo.bodyStrong)
                            Text(row.detail)
                                .font(Typo.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }

                if let footer = footer {
                    Text(footer)
                        .font(Typo.mono)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func badge(risks: Int, notices: Int, okText: String,
                       noticeText: (Int) -> String, riskText: (Int) -> String) -> (text: String, level: BadgeLevel) {
        if risks > 0 { return (riskText(risks), .critical) }
        if notices > 0 { return (noticeText(notices), .warning) }
        return (okText, .ok)
    }

    private func originalityBadge(_ findings: [OriginalityFinding]) -> (text: String, level: BadgeLevel) {
        guard ModelSpecCatalog.spec(for: info.modelIdentifier) != nil else {
            return (T("无对照数据", "No baseline"), .neutral)
        }
        let risks = findings.filter { $0.state == .inconsistent }.count
        let notices = findings.filter { $0.state == .notice }.count
        return badge(
            risks: risks,
            notices: notices,
            okText: T("符合官方规格", "Matches Apple spec"),
            noticeText: { T("\($0) 项需确认", "\($0) to confirm") },
            riskText: { T("\($0) 项与规格不符", "\($0) off-spec") }
        )
    }

    /// 基线名称用「覆盖」表述：同一标识符可能跨两代，直接写成机器名会让人误以为识别冲突
    private var baselineText: String? {
        guard let spec = ModelSpecCatalog.spec(for: info.modelIdentifier) else { return nil }
        return T("对照基线覆盖 \(spec.name) · \(ModelSpecCatalog.coverageText) · \(spec.source)",
                 "Baseline covers \(spec.name) · \(ModelSpecCatalog.coverageText) · \(spec.source)")
    }
}
