// Views/FirstRunGuide.swift
//
// 首次启动的说明页。目的不是"欢迎"，而是先说清楚这个工具看什么、不看什么，
// 避免把「不可用」误读成「有问题」，也避免把「符合规格」误读成「原装无修」。
import SwiftUI

struct FirstRunGuide: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            // 内容区可滚动，按钮固定在底部：窗口较矮时不会把按钮裁掉
            ScrollView {
                content
            }
            .frame(height: 430)

            HStack {
                Spacer()
                PrimaryButton(title: T("开始使用", "Get started"), icon: "arrow.right") {
                    onClose()
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 620)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(T("MacVerify 怎么用", "How MacVerify works")).font(Typo.display)
                Text(T("一句话：只报告本机能实测到的事实，取不到的就说取不到。",
                       "In one sentence: it reports only what this Mac can actually measure, and says so when it cannot."))
                    .font(Typo.body)
                    .foregroundColor(.secondary)
            }

            section(icon: "checkmark.seal", title: T("它做什么", "What it does"), lines: [
                T("从 IOKit、sysctl、系统命令读到本机硬件、电池、屏幕、外设与安全状态。",
                  "Reads hardware, battery, display, peripherals and security state from IOKit, sysctl and read-only system commands."),
                T("把同一件事从两条独立通路读一遍互相印证，改机型、刷序列号会在这里暴露。",
                  "Reads each fact twice from independent sources, so a swapped model or serial shows up."),
                T("把结果与 Apple 官方技术规格比对，并导出带指纹的报告。",
                  "Compares the result with Apple's published specs and exports a fingerprinted report.")
            ])

            section(icon: "exclamationmark.triangle", title: T("它不做什么", "What it does not do"), lines: [
                T("不联网、不上传、不改任何系统设置。",
                  "No network, no upload, no system changes."),
                T("不判断「是否原装」：与官方规格不符也可能是维修换板造成的。",
                  "It does not claim \"not genuine\": a mismatch can also come from a board-level repair."),
                T("不估算缺失值：显示「不可用」的地方就是本机没提供，不会用 0 或推测值顶替。",
                  "It never estimates: where it says unavailable, this Mac really did not provide it.")
            ])

            section(icon: "eye", title: T("怎么读结果", "How to read it"), lines: [
                T("先看概览页最上面的结论卡，再看下面按严重度排序的检查项。",
                  "Start with the verdict card on Overview, then the severity-sorted checks below it."),
                T("减号表示本机不提供；斜杠表示确实不存在（例如没插 USB 设备）。",
                  "A minus means this Mac does not expose it; a slash means it genuinely is not there, such as no USB device plugged in.")
            ])

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(icon: String, title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs + 2) {
            SectionHeader(title: title, icon: icon)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: Space.sm) {
                    Text("·").font(Typo.body).foregroundColor(.secondary)
                    Text(line)
                        .font(Typo.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
