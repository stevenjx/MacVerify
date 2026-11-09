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

                // 版本号与「重新扫描」同一条带边框的行里：左边版本，右边动作
                HStack(spacing: Space.sm) {
                    Text("v\(BuildInfo.version)")
                        .font(Typo.mono)
                        .foregroundColor(.secondary)
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
                .padding(.horizontal, Space.sm + 2)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Surface.well)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(Surface.border, lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 208)
        .background(Color(NSColor.controlBackgroundColor))
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
