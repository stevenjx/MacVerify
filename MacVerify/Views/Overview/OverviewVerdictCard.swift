// Views/Overview/OverviewVerdictCard.swift
//
// 概览页顶部结论条。整台机器的判断压成一行：结论 + 三个计数 + 两个动作。
// 结论文字直接取自报告生成逻辑，屏幕与导出文件说的是同一句话。
import SwiftUI
import AppKit

struct OverviewVerdictCard: View {
    let verdict: String
    let issues: Int
    let info: MacSystemInfo
    let battery: BatterySnapshot
    @Binding var selection: SidebarItem

    private var consistency: [AuditFinding] { ConsistencyAudit.run(info: info) }
    private var originality: [OriginalityFinding] {
        OriginalityCheck.run(info: info, battery: battery)
    }

    private var risks: Int {
        consistency.filter { $0.state == .inconsistent }.count
            + originality.filter { $0.state == .inconsistent }.count
    }

    private var confirmations: Int {
        consistency.filter { $0.state == .notice }.count
            + originality.filter { $0.state == .notice }.count
    }

    private var unavailable: Int {
        consistency.filter { $0.state == .unavailable }.count
            + originality.filter { $0.state == .unavailable }.count
    }

    private var level: BadgeLevel {
        if risks > 0 { return .critical }
        if issues > 0 { return .warning }
        return .ok
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.lg) {
            // 左侧色条：不读文字也能一眼看出结论。做成圆角内嵌块，
            // 不用 UnevenRoundedRectangle —— 那是 macOS 14 才有的 API，本项目最低支持 12。
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(level.color)
                .frame(width: 3, height: 34)

            Image(systemName: level.symbol)
                .font(Typo.icon(22, weight: .regular))
                .foregroundColor(level.color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(verdict)
                    .font(Typo.title)
                    .foregroundColor(level == .ok ? .primary : level.color)
                    .lineLimit(2)
                Text(T("序列号、崩溃记录、安全项、电池与规格核对的综合判断",
                       "Combined from serial, panics, security, battery and spec checks"))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: Space.md)

            HStack(spacing: Space.xl) {
                counter(T("不一致", "Mismatch"), risks, risks > 0 ? .critical : .neutral)
                counter(T("需确认", "To confirm"), confirmations, confirmations > 0 ? .warning : .neutral)
                counter(T("不可用", "Unavailable"), unavailable, .neutral)
            }

            Divider().frame(height: 26)

            HStack(spacing: Space.sm) {
                SecondaryButton(title: T("两次对比", "Compare"), icon: "arrow.left.arrow.right") {
                    selection = .comparison
                }
                PrimaryButton(title: T("导出报告", "Export"), icon: "square.and.arrow.up") {
                    ReportService.save(info: info, battery: battery)
                }
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Surface.fill))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Surface.border, lineWidth: 1)
        )
    }

    private func counter(_ title: String, _ value: Int, _ level: BadgeLevel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(Typo.metric)
                .foregroundColor(value == 0 ? .secondary : level.color)
            Text(title)
                .font(Typo.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 44, alignment: .leading)
    }
}
