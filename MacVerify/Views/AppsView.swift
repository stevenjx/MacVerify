// Views/AppsView.swift
//
// 我的应用：点图标直接打开对应项目的最新 release 页面。
// 页面上不写网址——地址对验机的人没有意义，点图标就是唯一动作。
import SwiftUI
import AppKit

struct AppsView: View {
    private struct Entry: Identifiable {
        let id: String
        let name: String
        let tagline: String
        let releaseURL: String
        let assetName: String?
    }

    private let entries: [Entry] = [
        Entry(id: "InfiniCal",
              name: "InfiniCal",
              tagline: T("电池校准", "Battery Management"),
              releaseURL: "https://github.com/stevenjx/InfiniCal/releases",
              assetName: "app_infinical"),
        Entry(id: "MacVerify",
              name: "MacVerify",
              tagline: T("二手 Mac 质检", "Secondhand Mac inspection"),
              releaseURL: "https://github.com/stevenjx/MacVerify/releases",
              assetName: nil)
    ]

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("我的应用", "My Apps"),
                subtitle: T("点应用图标打开最新版本", "Click an icon to open the latest release")
            )

            HStack(alignment: .top, spacing: Metrics.pageGap) {
                ForEach(entries) { entry in
                    tile(entry)
                }
            }

            NoticeBar(text: T("图标直接打开该项目的 GitHub Releases 页面，页面里可以下载最新安装包。",
                              "The icon opens the project's GitHub Releases page, where the latest build can be downloaded."),
                      level: .neutral)
        }
    }

    private func tile(_ entry: Entry) -> some View {
        Button {
            if let url = URL(string: entry.releaseURL) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(spacing: Space.sm) {
                icon(for: entry)
                    .frame(width: 88, height: 88)

                Text(entry.name)
                    .font(Typo.bodyStrong)
                    .foregroundColor(.primary)
                Text(entry.tagline)
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xl)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Surface.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Surface.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.name)
        .accessibilityHint(T("打开 GitHub Releases 页面", "Opens the GitHub Releases page"))
    }

    @ViewBuilder
    private func icon(for entry: Entry) -> some View {
        if let asset = entry.assetName {
            Image(asset)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .cornerRadius(20)
        } else {
            // 当前 App 没有单独的图标资源，直接用运行中的图标
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(20)
        }
    }
}
