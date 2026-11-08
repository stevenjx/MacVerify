// Views/Overview/OverviewView.swift
//
// 概览页只做组装：结论 → 身份 → 两类核对 → 关键检查项 → 使用强度。
// 具体内容拆在 Overview/ 下的几个文件里，避免这个文件继续长到 400 行。
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var system: SystemInfoStore
    @EnvironmentObject private var battery: BatteryStore
    @Binding var selection: SidebarItem

    private var info: MacSystemInfo { system.info }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("设备概览", "Overview"),
                subtitle: T("本机硬件、电池与安全状态一次性核对", "Hardware, battery and security at a glance"),
                trailing: AnyView(
                    SecondaryButton(title: T("刷新", "Refresh"), icon: "arrow.clockwise") {
                        system.refresh()
                        battery.refresh()
                    }
                )
            )

            verdictCard
            OverviewIdentityCard(info: info)
            OverviewAuditCards(info: info, battery: battery.battery)
            OverviewChecksSection(info: info, battery: battery.battery, selection: $selection)
            OverviewUsageSection(info: info)

            NoticeBar(
                text: T("所有数据均来自本机 IOKit、sysctl 与系统命令，不修改任何系统设置。取不到的项显示「不可用」或「无法读取」，不会用 0 或估算值代替。",
                       "All values come from IOKit, sysctl and read-only system commands. Nothing is modified. Missing values are shown as unavailable or unreadable — never replaced with 0 or an estimate."),
                level: .neutral
            )
        }
    }

    /// 结论卡放在最上面：先看这台机器「有没有问题」，再往下看是哪一项。
    /// 结论文字直接取自报告生成逻辑，保证屏幕与导出文件说的是同一句话。
    private var verdictCard: some View {
        let report = ReportService.build(info: info, battery: battery.battery)
        return OverviewVerdictCard(
            verdict: report.verdict,
            issues: report.issues,
            info: info,
            battery: battery.battery,
            selection: $selection
        )
    }
}
