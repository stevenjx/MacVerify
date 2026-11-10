// Views/RootView.swift
import SwiftUI
import AppKit

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview
    case hardware
    case security
    case display
    case storage
    case performance
    case input
    case audio
    case camera
    case touchID
    case ports
    case battery
    case loadTest
    case power
    case peripherals
    case apps
    case comparison
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return T("概览", "Overview")
        case .hardware: return T("设备信息", "Device")
        case .security: return T("安全与合规", "Security")
        case .display: return T("显示屏", "Display")
        case .storage: return T("存储", "Storage")
        case .performance: return T("性能测试", "Benchmarks")
        case .input: return T("键盘与触控板", "Input")
        case .audio: return T("扬声器与麦克风", "Speakers & Mic")
        case .camera: return T("摄像头", "Camera")
        case .touchID: return "Touch ID"
        case .ports: return T("接口测试", "Port Test")
        case .battery: return T("电池", "Battery")
        case .loadTest: return T("电池负载测试", "Load Test")
        case .power: return T("供电", "Power")
        case .peripherals: return T("外设", "Peripherals")
        case .apps: return T("我的应用", "My Apps")
        case .comparison: return T("两次对比", "Compare")
        case .about: return T("关于", "About")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .hardware: return "cpu"
        case .security: return "shield"
        case .display: return "display"
        case .storage: return "internaldrive"
        case .performance: return "speedometer"
        case .input: return "keyboard"
        case .audio: return "speaker.wave.2"
        case .camera: return "camera"
        case .touchID: return "touchid"
        case .ports: return "cable.connector"
        case .battery: return "battery.100"
        case .loadTest: return "waveform.path.ecg"
        case .power: return "powerplug"
        case .peripherals: return "cable.connector"
        case .apps: return "square.stack.3d.up"
        case .comparison: return "arrow.left.arrow.right"
        case .about: return "info.circle"
        }
    }

    /// 只有「跑一次才知道结果」的交互测试才需要完成标记；
    /// 概览、设备信息这类读一次就有数据的页面不显示圆圈，避免一屏全是无意义的勾。
    var testKey: String? {
        switch self {
        case .audio: return "audio"
        case .camera: return "camera"
        case .touchID: return "touchID"
        case .ports: return "ports"
        case .performance: return "performance"
        case .input: return "input"
        case .loadTest: return "loadTest"
        default: return nil
        }
    }

    static var groups: [(title: String, items: [SidebarItem])] {
        [
            (T("检测", "INSPECTION"), [.overview, .hardware, .security, .display, .storage]),
            (T("测试", "TESTS"), [.performance, .input, .audio, .camera, .touchID, .ports,
                                  .loadTest, .battery, .power]),
            (T("接口", "PORTS"), [.peripherals]),
            (T("其他", "OTHER"), [.apps, .comparison, .about])
        ]
    }
}

struct RootView: View {
    @EnvironmentObject private var system: SystemInfoStore
    @EnvironmentObject private var battery: BatteryStore
    @ObservedObject private var localization = Localization.shared
    @ObservedObject private var themeStore = ThemeStore.shared
    @AppStorage("macverify.guide.seen") private var guideSeen = false
    @ObservedObject private var progress = TestProgress.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var showGuide = false

    @State private var selection: SidebarItem = {
        if let raw = ProcessInfo.processInfo.environment["MACVERIFY_PAGE"],
           let item = SidebarItem(rawValue: raw) {
            return item
        }
        return .overview
    }()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 1000, minHeight: 680)
        // 不透明底色：避免新版 macOS 的玻璃材质让内容透出桌面
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(themeStore.theme.colorScheme)
        .environment(\.locale, localization.locale)
        .sheet(isPresented: $showGuide) {
            FirstRunGuide {
                guideSeen = true
                showGuide = false
            }
        }
        .onAppear {
            if !guideSeen { showGuide = true }
        }
        .task {
            // 启动时查一次（6 小时内不重复），有新版本就在侧栏版本号处提示
            await updates.checkIfNeeded()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部不再放应用图标与名字：窗口标题栏已经写了 MacVerify，
            // 这里重复一次只会把导航整体往下推。
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(SidebarItem.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.title)
                                .font(Typo.captionStrong)
                                .foregroundColor(.secondary.opacity(0.85))
                                .padding(.horizontal, 16)
                                .padding(.bottom, 3)

                            ForEach(group.items) { item in
                                sidebarRow(item)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)

            VStack(spacing: Space.sm) {
                Divider().opacity(0.5)

                // 开发者信息居中：它是署名，不是导航项
                VStack(spacing: 1) {
                    Text("Infinity Computer")
                        .font(Typo.captionStrong)
                        .foregroundColor(.primary)
                    Text(T("开发者 StevenYang", "Developer StevenYang"))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

                versionRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: 208)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - 版本行

    /// 版本号与新版本提示。侧栏只有 208pt，横着放不下「v1.0.10 · 1.0.12 可更新」，
    /// 所以提示另起一行，仍在同一个描边框里。
    private var versionRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Space.sm) {
                Button {
                    Task { await updates.handleVersionTap() }
                } label: {
                    HStack(spacing: 4) {
                        if case .available = updates.status {
                            Circle()
                                .fill(StatusPalette.warning)
                                .frame(width: 5, height: 5)
                        }
                        Text("v\(BuildInfo.version)")
                            .font(Typo.mono)
                            .foregroundColor(hasUpdate ? StatusPalette.warning : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(versionTooltip)
                .accessibilityLabel(versionAccessibilityLabel)

                Spacer(minLength: Space.xs)

                Button(action: { system.refresh(); battery.refresh() }) {
                    HStack(spacing: 4) {
                        if system.isScanning {
                            ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise").font(Typo.captionStrong)
                        }
                        Text(T("重新扫描", "Rescan")).font(Typo.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(system.isScanning)
            }

            if let line = updateLine {
                Button {
                    Task { await updates.handleVersionTap() }
                } label: {
                    HStack(spacing: 4) {
                        if case .downloading = updates.status {
                            ProgressView().controlSize(.small).scaleEffect(0.5).frame(width: 9, height: 9)
                        } else {
                            Image(systemName: line.icon).font(Typo.icon(9, weight: .semibold))
                        }
                        Text(line.text)
                            .font(Typo.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundColor(line.level.color)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(versionTooltip)
            }
        }
        .padding(.horizontal, Space.sm + 2)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Surface.well)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(hasUpdate ? StatusPalette.warning.opacity(0.45) : Surface.border, lineWidth: 1)
        )
    }

    private var hasUpdate: Bool {
        if case .available = updates.status { return true }
        return false
    }

    /// 新版本、下载中、已下载三种状态各给一行说明；检查中与失败都不出声，
    /// 免得侧栏因为网络问题闪来闪去。
    private var updateLine: (text: String, icon: String, level: BadgeLevel)? {
        switch updates.status {
        case .available(let release):
            return (T("\(release.version) 可下载", "\(release.version) available"), "arrow.down.circle.fill", .warning)
        case .downloading(let progress, _):
            return (T("下载中 \(Int(progress * 100))%", "Downloading \(Int(progress * 100))%"),
                    "arrow.down.circle", .warning)
        case .downloaded:
            return (T("已下载，点此查看", "Downloaded · show in Finder"), "checkmark.circle.fill", .ok)
        case .idle, .checking, .upToDate, .failed:
            return nil
        }
    }

    private var versionTooltip: String {
        switch updates.status {
        case .available(let release):
            return T("有新版本 \(release.version)，点击下载 \(release.assetName)",
                     "Version \(release.version) is available — click to download \(release.assetName)")
        case .downloading:
            return T("正在下载最新版 DMG", "Downloading the latest DMG")
        case .downloaded(let url):
            return T("已下载到 \(url.path)，点击在访达中显示", "Saved to \(url.path) — click to show in Finder")
        case .upToDate(let version):
            return T("已是最新版本（远端 \(version)）", "Up to date (latest is \(version))")
        case .failed(let message):
            return T("检查更新失败：\(message)，点击重试", "Update check failed: \(message) — click to retry")
        case .checking:
            return T("正在检查新版本", "Checking for updates")
        case .idle:
            return T("点击检查新版本", "Click to check for updates")
        }
    }

    private var versionAccessibilityLabel: String {
        if case .available(let release) = updates.status {
            return T("版本 \(BuildInfo.version)，有新版本 \(release.version) 可下载",
                     "Version \(BuildInfo.version), \(release.version) is available to download")
        }
        return T("版本 \(BuildInfo.version)", "Version \(BuildInfo.version)")
    }

    /// 已测：实心绿勾；未测：虚线圆圈。不用灰色实心圆——那和「不可用」的含义撞车。
    @ViewBuilder
    private func testBadge(done: Bool) -> some View {
        if done {
            Image(systemName: "checkmark.circle.fill")
                .font(Typo.icon(11, weight: .semibold))
                .foregroundColor(StatusPalette.ok)
                .accessibilityLabel(T("已测试", "Tested"))
        } else {
            Circle()
                .strokeBorder(
                    Color.secondary.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1, dash: [2.5, 2])
                )
                .frame(width: 10, height: 10)
                .accessibilityLabel(T("未测试", "Not tested"))
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        let isSelected = selection == item
        return Button(action: { selection = item }) {
            HStack(spacing: Space.sm + 1) {
                Image(systemName: item.icon)
                    .font(Typo.icon(13, weight: .medium))
                    .frame(width: 18)
                    .foregroundColor(isSelected ? Color.accentColor : .secondary)
                Text(item.title)
                    .font(isSelected ? Typo.bodyStrong : Typo.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: Space.xs)

                if let key = item.testKey {
                    testBadge(done: progress.isCompleted(key))
                }
            }
            .padding(.horizontal, Space.sm + 1)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            // 选中态改为「淡色块 + 左侧高亮条」：整块铺满饱和色的视觉压迫感太强
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 2.5)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, Space.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .overview: OverviewView(selection: $selection)
        case .hardware: HardwareView()
        case .security: SecurityView()
        case .display: DisplayView()
        case .storage: StorageView()
        case .performance: PerformanceView()
        case .input: InputTestView()
        case .audio: AudioTestView()
        case .camera: CameraTestView()
        case .touchID: TouchIDTestView()
        case .ports: PortTestView()
        case .battery: BatteryView()
        case .loadTest: LoadTestView()
        case .power: PowerView()
        case .peripherals: PeripheralsView()
        case .apps: AppsView()
        case .comparison: ComparisonView()
        case .about: AboutView()
        }
    }
}

/// 统一的内容容器：滚动 + 内边距 + 最大宽度。
/// 限宽是为了不让文字行横跨整个屏幕；窗口更宽时内容居中，两侧留出呼吸而不是把行拉长。
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.pageGap) {
                content
            }
            .padding(Metrics.pagePadding)
            .frame(maxWidth: Metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
