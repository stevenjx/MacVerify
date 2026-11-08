// Views/AboutView.swift
//
// 关于页：应用信息与偏好设置并排，说明单独一行。
// 改造前四个竖卡 + 一行按钮，右边整片空白。
import SwiftUI
import AppKit

struct AboutView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject private var themeStore = ThemeStore.shared
    @EnvironmentObject private var system: SystemInfoStore

    private let projectURL = "https://github.com/stevenjx/MacVerify"

    var body: some View {
        PageScroll {
            PageHeader(title: T("关于", "About"), subtitle: T("语言、外观与版本信息", "Language, appearance and version"))

            HStack(alignment: .top, spacing: Metrics.pageGap) {
                Card(title: T("应用", "App"), icon: "app.badge") {
                    VStack(alignment: .leading, spacing: Space.md) {
                        HStack(spacing: Space.md) {
                            Image(nsImage: NSApplication.shared.applicationIconImage)
                                .resizable()
                                .frame(width: 56, height: 56)
                                .cornerRadius(12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("MacVerify").font(Typo.title)
                                Text(T("二手 Mac 硬件质检工具", "Hardware inspection for used Macs"))
                                    .font(Typo.caption)
                                    .foregroundColor(.secondary)
                                Text(T("版本 \(BuildInfo.version)（\(BuildInfo.build)）",
                                       "Version \(BuildInfo.version) (\(BuildInfo.build))"))
                                    .font(Typo.mono)
                                    .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 0)
                        }

                        HStack(spacing: Space.sm) {
                            SecondaryButton(title: "GitHub", icon: "link") {
                                if let url = URL(string: projectURL) { NSWorkspace.shared.open(url) }
                            }
                            SecondaryButton(title: T("导出报告", "Export"), icon: "square.and.arrow.down") {
                                ReportService.save(info: system.info, battery: BatteryStore.readBattery())
                            }
                            SecondaryButton(title: T("复制报告", "Copy"), icon: "doc.on.doc") {
                                ReportService.copyMarkdown(info: system.info, battery: BatteryStore.readBattery())
                            }
                        }

                        Text(T("检测时间 \(Format.dateTime(system.info.scannedAt))",
                               "Scanned \(Format.dateTime(system.info.scannedAt))"))
                            .font(Typo.mono)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 400)

                Card(title: T("偏好设置", "Preferences"), icon: "gearshape") {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            SectionHeader(title: T("界面语言", "LANGUAGE"))
                            Picker("", selection: Binding(
                                get: { localization.language },
                                set: { localization.language = $0 }
                            )) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Text(T("切换后立即生效。系统语言为中文时选择“跟随系统”会自动使用简体中文。",
                                   "Changes apply immediately. With Follow System, a Chinese system language selects Simplified Chinese."))
                                .font(Typo.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: Space.xs) {
                            SectionHeader(title: T("外观", "APPEARANCE"))
                            Picker("", selection: Binding(
                                get: { themeStore.theme },
                                set: { themeStore.theme = $0 }
                            )) {
                                ForEach(AppTheme.allCases) { theme in
                                    Text(theme.displayName).tag(theme)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                }
            }

            Card(title: T("说明", "Notes"), icon: "info.circle") {
                HStack(alignment: .top, spacing: Space.xl) {
                    Text(T("所有检测均在本机完成，不联网、不上传数据。数据来源包括 IOKit、sysctl、CoreGraphics 与只读系统命令。",
                           "Everything runs locally — no network calls, no uploads. Data comes from IOKit, sysctl, CoreGraphics and read-only system commands."))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(T("机型名称与面板信息来自 Apple 公开资料。部分传感器（SMART、温度）在 Apple Silicon 上不向用户态开放，界面会如实显示“不可用”，不会估算或补值。",
                           "Model names come from public Apple documentation. Some sensors (SMART, temperature) are not exposed on Apple Silicon; the app shows them as unavailable rather than guessing."))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(T("通用", "General")).font(Typo.title)

            VStack(alignment: .leading, spacing: 5) {
                Text(T("语言", "Language")).font(Typo.caption).foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { localization.language },
                    set: { localization.language = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(T("外观", "Appearance")).font(Typo.caption).foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { themeStore.theme },
                    set: { themeStore.theme = $0 }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()
            Text(T("MacVerify \(BuildInfo.version) · 本机检测，不上传数据", "MacVerify \(BuildInfo.version) · Local only, no uploads"))
                .font(Typo.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(20)
        .frame(width: 380, height: 260)
    }
}
