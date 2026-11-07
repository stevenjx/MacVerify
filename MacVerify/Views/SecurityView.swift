// Views/SecurityView.swift
import SwiftUI

struct SecurityView: View {
    @EnvironmentObject private var system: SystemInfoStore

    private var info: MacSystemInfo { system.info }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("安全与合规", "Security"),
                subtitle: T("二手设备交易前需确认的四项状态", "Four states worth confirming before buying"),
                trailing: AnyView(
                    SecondaryButton(title: T("重新读取", "Reload"), icon: "arrow.clockwise") { system.refresh() }
                )
            )

            securityCard
            panicCard
            NoticeBar(
                text: T("以上状态由系统命令只读获取，仅反映当前登录用户可见的信息。激活锁状态需要连接网络后由系统返回。",
                       "These states are read from read-only system commands and reflect what the current user can see. Activation Lock status requires a network connection."),
                level: .neutral
            )
        }
    }

    private var securityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: T("设备状态", "DEVICE STATE"))

                securityRow(
                    title: T("激活锁", "Activation Lock"),
                    value: triState(info.activationLock),
                    level: info.activationLock == true ? .warning : (info.activationLock == false ? .ok : .neutral),
                    detail: T("开启时说明设备与原 Apple ID 绑定，需原机主退出后才能正常使用。",
                              "When enabled, the Mac is bound to an Apple ID and must be removed by the previous owner.")
                )

                securityRow(
                    title: T("文件保险箱", "FileVault"),
                    value: triState(info.fileVault),
                    level: info.fileVault == true ? .ok : .neutral,
                    detail: T("全盘加密。二手设备建议抹盘后重新开启。",
                              "Full-disk encryption. Re-enable it after erasing a used Mac.")
                )

                securityRow(
                    title: T("系统完整性保护 (SIP)", "System Integrity Protection"),
                    value: triState(info.sipEnabled),
                    level: info.sipEnabled == true ? .ok : (info.sipEnabled == false ? .warning : .neutral),
                    detail: T("关闭通常意味着系统被改动过，需确认原因。",
                              "Disabled usually means the system was modified — confirm why.")
                )

                securityRow(
                    title: T("门禁 (Gatekeeper)", "Gatekeeper"),
                    value: triState(info.gatekeeperEnabled),
                    level: info.gatekeeperEnabled == true ? .ok : (info.gatekeeperEnabled == false ? .warning : .neutral),
                    detail: T("控制未签名应用的运行权限。",
                              "Controls whether unsigned apps may run.")
                )

                securityRow(
                    title: T("MDM 注册", "MDM enrollment"),
                    value: triState(info.mdmEnrolled),
                    level: info.mdmEnrolled == true ? .warning : (info.mdmEnrolled == false ? .ok : .neutral),
                    detail: T("企业或学校统一管理。已注册的设备可能被远程锁定或抹除。",
                              "Managed by an organization. Enrolled devices can be remotely locked or wiped.")
                )

                securityRow(
                    title: T("远程管理配置", "Remote management profile"),
                    value: info.remoteManagement == true ? T("存在", "Present") : T("未发现", "Not found"),
                    level: info.remoteManagement == true ? .warning : .ok,
                    detail: T("检查 /Library/Managed Preferences 下的描述文件。",
                              "Checks profiles under /Library/Managed Preferences."),
                    isLast: true
                )
            }
        }
    }

    private var panicCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: T("稳定性记录", "STABILITY"))
                    Spacer()
                    StatusBadge(
                        text: panicBadgeText,
                        level: !info.panicScanAvailable ? .neutral : (info.panicLogCount > 0 ? .warning : .ok)
                    )
                }

                Text(T("内核崩溃日志位于 /Library/Logs/DiagnosticReports。频繁崩溃可能来自内存、主板或外设故障。",
                       "Kernel panic reports live in /Library/Logs/DiagnosticReports. Frequent panics can indicate memory, logic board or peripheral faults."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let last = info.lastPanicDate {
                    InfoRow(label: T("最近一次崩溃", "Most recent"), value: Format.dateTime(last), isLast: true)
                }
            }
        }
    }

    private func triState(_ value: Bool?) -> String {
        guard let value = value else { return T("无法读取", "Unavailable") }
        return value ? T("已开启", "Enabled") : T("已关闭", "Disabled")
    }

    /// 崩溃日志目录可能因权限不可读。不可读 ≠ 没有崩溃，必须区分。
    private var panicBadgeText: String {
        guard info.panicScanAvailable else { return T("无法读取", "Unavailable") }
        return info.panicLogCount > 0
            ? T("\(info.panicLogCount) 条崩溃日志", "\(info.panicLogCount) panic logs")
            : T("无崩溃日志", "No panic logs")
    }

    private func securityRow(title: String, value: String, level: BadgeLevel, detail: String, isLast: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: level.symbol)
                    .font(.system(size: 13))
                    .foregroundColor(level.color)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(detail).font(.system(size: 10.5)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                Text(value).font(.system(size: 12, weight: .medium)).foregroundColor(level == .neutral ? .secondary : level.color)
            }
            .padding(.vertical, 8)
            if !isLast { Divider().opacity(0.5) }
        }
    }
}
