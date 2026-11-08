// Views/Overview/OverviewAuditCards.swift
//
// 一致性核验 + 原装性核对。两张卡并排，行内只留「结论 + 一句依据」，
// 依据超过一行就省略——完整措辞在导出的报告里，这里不重复堆字。
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

        HStack(alignment: .top, spacing: Metrics.pageGap) {
            card(
                title: T("一致性核验", "Consistency"),
                icon: "arrow.left.arrow.right",
                explanation: T("同一事实从系统报告与内核接口各读一次，两路必须一致。",
                               "Each fact is read from the system report and the kernel; both must agree."),
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
                title: T("原装性核对", "Originality"),
                icon: "checkmark.seal",
                explanation: T("对照 Apple 官方规格。不匹配只说明与官方规格不符，不等于被改装。",
                               "Compared with Apple's published specs. A mismatch is not proof of modification."),
                rows: originality.map {
                    AuditRow(title: $0.title, detail: $0.detail, level: $0.state.badgeLevel)
                },
                badge: originalityBadge(originality),
                footer: baselineText
            )
        }
    }

    // MARK: - 局部

    private func card(title: String, icon: String, explanation: String, rows: [AuditRow],
                      badge: (text: String, level: BadgeLevel), footer: String?) -> some View {
        Card(title: title, icon: icon, trailing: AnyView(
            StatusBadge(text: badge.text, level: badge.level)
        )) {
            VStack(alignment: .leading, spacing: 0) {
                Text(explanation)
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Space.xs + 2)

                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: Space.sm) {
                        StatusDot(level: row.level, size: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.title)
                                .font(Typo.captionStrong)
                                .lineLimit(1)
                            Text(row.detail)
                                .font(Typo.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                    .help(row.detail)
                }

                if let footer = footer {
                    Text(footer)
                        .font(Typo.mono)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .padding(.top, Space.xs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
        return T("对照基线覆盖 \(spec.name) · \(ModelSpecCatalog.coverageText)",
                 "Baseline covers \(spec.name) · \(ModelSpecCatalog.coverageText)")
    }
}
