// Views/AboutView.swift
import SwiftUI
import AppKit

struct AboutView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject private var themeStore = ThemeStore.shared
    @EnvironmentObject private var system: SystemInfoStore

    private let projectURL = "https://github.com/stevenjx/MacCheck"

    var body: some View {
        PageScroll {
            PageHeader(title: T("关于", "About"), subtitle: T("语言、外观与版本信息", "Language, appearance and version"))

            HStack(spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .cornerRadius(14)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MacCheck").font(.system(size: 20, weight: .bold))
                    Text(T("二手 Mac 硬件质检工具", "Hardware inspection for used Macs"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(T("版本 \(BuildInfo.version)（\(BuildInfo.build)）", "Version \(BuildInfo.version) (\(BuildInfo.build))"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
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
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
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

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: T("说明", "NOTES"))
                    Text(T("所有检测均在本机完成，不联网、不上传数据。数据来源包括 IOKit、sysctl、CoreGraphics 与只读系统命令。",
                           "Everything runs locally — no network calls, no uploads. Data comes from IOKit, sysctl, CoreGraphics and read-only system commands."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(T("机型名称与面板信息来自 Apple 公开资料。部分传感器（SMART、温度）在 Apple Silicon 上不向用户态开放，界面会如实显示“不可用”，不会估算或补值。",
                           "Model names come from public Apple documentation. Some sensors (SMART, temperature) are not exposed on Apple Silicon; the app shows them as unavailable rather than guessing."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                SecondaryButton(title: "GitHub", icon: "link") {
                    if let url = URL(string: projectURL) { NSWorkspace.shared.open(url) }
                }
                SecondaryButton(title: T("复制系统报告", "Copy system report"), icon: "doc.on.doc") {
                    copyReport()
                }
                Spacer()
                Text(T("检测时间 \(Format.dateTime(system.info.scannedAt))", "Scanned \(Format.dateTime(system.info.scannedAt))"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func copyReport() {
        let info = system.info
        let report = """
        MacCheck \(BuildInfo.version) (\(BuildInfo.build))
        Model: \(info.modelDisplayName) [\(info.modelIdentifier)]
        Serial: \(info.serialNumber)
        Chip: \(info.chipName) · \(info.architecture)
        Memory: \(info.memoryGB) GB
        Storage: \(info.storage.totalGB) GB · \(info.storage.deviceName)
        macOS: \(info.osVersion) (\(info.osBuild))
        Activation Lock: \(String(describing: info.activationLock))
        FileVault: \(String(describing: info.fileVault))
        SIP: \(String(describing: info.sipEnabled))
        MDM: \(String(describing: info.mdmEnrolled))
        Panics: \(info.panicLogCount)
        Display: \(info.display.inchText) \(info.display.resolutionText) \(info.display.name)
        """
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
    }
}

struct SettingsView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(T("通用", "General")).font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(T("语言", "Language")).font(.system(size: 11)).foregroundColor(.secondary)
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

            VStack(alignment: .leading, spacing: 6) {
                Text(T("外观", "Appearance")).font(.system(size: 11)).foregroundColor(.secondary)
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
            Text(T("MacCheck \(BuildInfo.version) · 本机检测，不上传数据", "MacCheck \(BuildInfo.version) · Local only, no uploads"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(20)
        .frame(width: 380, height: 260)
    }
}
