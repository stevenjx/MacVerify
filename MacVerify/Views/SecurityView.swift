// Views/SecurityView.swift
//
// 六项安全状态排成 2×3 网格，每项一块。改造前是六行「标题 + 说明 + 右侧状态」，
// 一屏只放得下这六行，下半页全空。
import SwiftUI

struct SecurityView: View {
    @EnvironmentObject private var system: SystemInfoStore

    private var info: MacSystemInfo { system.info }

    private let columns = [
        GridItem(.flexible(), spacing: Space.sm),
        GridItem(.flexible(), spacing: Space.sm),
        GridItem(.flexible(), spacing: Space.sm)
    ]

    private var states: [(title: String, value: String, level: BadgeLevel, detail: String)] {
        [
            (T("激活锁", "Activation Lock"),
             triState(info.activationLock),
             info.activationLock == true ? .warning : (info.activationLock == false ? .ok : .neutral),
             T("开启表示仍绑定原 Apple ID，需原机主退出。",
               "Enabled means it is still bound to an Apple ID.")),

            (T("文件保险箱", "FileVault"),
             triState(info.fileVault),
             info.fileVault == true ? .ok : .neutral,
             T("全盘加密，二手设备建议抹盘后重新开启。",
               "Full-disk encryption. Re-enable after erasing a used Mac.")),

            (T("系统完整性保护", "SIP"),
             triState(info.sipEnabled),
             info.sipEnabled == true ? .ok : (info.sipEnabled == false ? .warning : .neutral),
             T("关闭通常意味着系统被改动过。",
               "Disabled usually means the system was modified.")),

            (T("门禁", "Gatekeeper"),
             triState(info.gatekeeperEnabled),
             info.gatekeeperEnabled == true ? .ok : (info.gatekeeperEnabled == false ? .warning : .neutral),
             T("控制未签名应用的运行权限。",
               "Controls whether unsigned apps may run.")),

            (T("MDM 注册", "MDM enrollment"),
             triState(info.mdmEnrolled),
             info.mdmEnrolled == true ? .warning : (info.mdmEnrolled == false ? .ok : .neutral),
             T("已注册的设备可能被远程锁定或抹除。",
               "Enrolled devices can be locked or wiped remotely.")),

            (T("远程管理", "Remote management"),
             info.remoteManagement == true ? T("存在", "Present") : T("未发现", "Not found"),
             info.remoteManagement == true ? .warning : .ok,
             T("检查 /Library/Managed Preferences 下的描述文件。",
               "Checks profiles under /Library/Managed Preferences."))
        ]
    }

    private var panicFacts: [Fact] {
        var facts: [Fact] = [
            Fact(T("崩溃日志", "Panic logs"), panicCountText, state: info.panicScanAvailable ? .normal : .unavailable)
        ]
        if let last = info.lastPanicDate {
            facts.append(Fact(T("最近一次", "Most recent"), Format.dateTime(last)))
        }
        facts.append(Fact(T("日志目录", "Log directory"), "/Library/Logs/DiagnosticReports", mono: true))
        return facts
    }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("安全与合规", "Security"),
                subtitle: T("二手设备交易前需确认的状态", "States worth confirming before buying"),
                trailing: AnyView(
                    SecondaryButton(title: T("重新读取", "Reload"), icon: "arrow.clockwise") { system.refresh() }
                )
            )

            Card(title: T("设备状态", "Device state"), icon: "lock.shield") {
                LazyVGrid(columns: columns, spacing: Space.sm) {
                    ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                        tile(state.title, state.value, state.level, state.detail)
                    }
                }
            }

            Card(title: T("稳定性记录", "Stability"),
                 icon: "waveform.path.ecg",
                 trailing: AnyView(
                    StatusBadge(
                        text: panicBadgeText,
                        level: !info.panicScanAvailable ? .neutral : (info.panicLogCount > 0 ? .warning : .ok)
                    )
                 )) {
                FactGrid(facts: panicFacts, columns: 2)
            }

            NoticeBar(
                text: T("以上状态由系统命令只读获取，仅反映当前登录用户可见的信息。激活锁状态需要连接网络后由系统返回。",
                       "These states are read from read-only system commands and reflect what the current user can see. Activation Lock requires a network connection."),
                level: .neutral
            )
        }
    }

    private func tile(_ title: String, _ value: String, _ level: BadgeLevel, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Space.xs + 1) {
                StatusDot(level: level, size: 6)
                Text(title).font(Typo.captionStrong).lineLimit(1)
                Spacer(minLength: Space.xs)
                Text(value)
                    .font(Typo.caption)
                    .foregroundColor(level == .neutral ? .secondary : level.color)
                    .lineLimit(1)
            }
            Text(detail)
                .font(Typo.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Surface.well))
    }

    private func triState(_ value: Bool?) -> String {
        guard let value = value else { return T("无法读取", "Unavailable") }
        return value ? T("已开启", "Enabled") : T("已关闭", "Disabled")
    }

    private var panicCountText: String {
        guard info.panicScanAvailable else { return T("无法读取", "Unavailable") }
        return info.panicLogCount > 0
            ? T("\(info.panicLogCount) 条", "\(info.panicLogCount)")
            : T("无记录", "None")
    }

    /// 崩溃日志目录可能因权限不可读。不可读 ≠ 没有崩溃，必须区分。
    private var panicBadgeText: String {
        guard info.panicScanAvailable else { return T("无法读取", "Unavailable") }
        return info.panicLogCount > 0
            ? T("\(info.panicLogCount) 条崩溃日志", "\(info.panicLogCount) panic logs")
            : T("无崩溃日志", "No panic logs")
    }
}
