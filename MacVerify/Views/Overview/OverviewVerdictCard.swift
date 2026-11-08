// Views/Overview/OverviewVerdictCard.swift
//
// 概览页顶部结论卡。改造前概览页一上来就是设备照片和两张长卡片，
// 「这台机器到底有没有问题」要自己滚到底再拼结论。
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
        HStack(spacing: 0) {
            // 左侧色条：状态的第一眼信号，不依赖文字
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(level.color)
                .frame(width: 3)
                .padding(.vertical, Space.xs)

            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verdict)
                        .font(Typo.title)
                        .foregroundColor(level == .ok ? .primary : level.color)
                    Spacer()
                    if issues == 0 {
                        StatusBadge(text: T("通过", "Clear"), level: .ok)
                    } else {
                        StatusBadge(text: T("\(issues) 项待确认", "\(issues) to confirm"), level: level)
                    }
                }

                Text(T("序列号、崩溃记录、安全项、电池与规格核对的综合判断；与导出的报告结论一致。",
                       "A combined judgement over serial, panics, security, battery and spec checks — the same wording as the exported report."))
                    .font(Typo.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.sm) {
                    chip(T("不一致", "Mismatch"), risks, risks > 0 ? .critical : .ok)
                    chip(T("需确认", "To confirm"), confirmations, confirmations > 0 ? .warning : .neutral)
                    chip(T("不可用", "Unavailable"), unavailable, .neutral)
                    Spacer()
                    SecondaryButton(title: T("两次对比", "Compare"), icon: "arrow.left.arrow.right") {
                        selection = .comparison
                    }
                    SecondaryButton(title: T("导出报告", "Export report"), icon: "square.and.arrow.up") {
                        ReportService.save(info: info, battery: battery)
                    }
                }
            }
            .padding(Space.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Surface.fill))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Surface.border, lineWidth: 1)
        )
    }

    private func chip(_ title: String, _ count: Int, _ level: BadgeLevel) -> some View {
        HStack(spacing: Space.xs) {
            Text(title).font(Typo.caption).foregroundColor(.secondary)
            Text("\(count)")
                .font(Typo.captionStrong)
                .foregroundColor(count == 0 ? .secondary : level.color)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(level.color.opacity(count == 0 ? 0.04 : 0.10))
        .cornerRadius(Radius.badge)
    }
}
