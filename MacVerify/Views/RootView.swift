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
    case battery
    case loadTest
    case power
    case peripherals
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
        case .battery: return T("电池", "Battery")
        case .loadTest: return T("电池负载测试", "Load Test")
        case .power: return T("供电", "Power")
        case .peripherals: return T("外设", "Peripherals")
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
        case .battery: return "battery.100"
        case .loadTest: return "waveform.path.ecg"
        case .power: return "powerplug"
        case .peripherals: return "cable.connector"
        case .comparison: return "arrow.left.arrow.right"
        case .about: return "info.circle"
        }
    }

    static var groups: [(title: String, items: [SidebarItem])] {
        [
            (T("检测", "INSPECTION"), [.overview, .hardware, .security, .display, .storage]),
            (T("测试", "TESTS"), [.performance, .input, .battery, .loadTest, .power]),
            (T("接口", "PORTS"), [.peripherals]),
            (T("其他", "OTHER"), [.comparison, .about])
        ]
    }
}

struct RootView: View {
    @EnvironmentObject private var system: SystemInfoStore
    @EnvironmentObject private var battery: BatteryStore
    @ObservedObject private var localization = Localization.shared
    @ObservedObject private var themeStore = ThemeStore.shared

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
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .cornerRadius(6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacVerify").font(.system(size: 13, weight: .semibold))
                    Text(T("二手 Mac 质检", "Used Mac Inspection"))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SidebarItem.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 14)
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

            VStack(alignment: .leading, spacing: 6) {
                Divider().opacity(0.5)
                HStack {
                    Text("v\(BuildInfo.version) (\(BuildInfo.build))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { system.refresh(); battery.refresh() }) {
                        HStack(spacing: 4) {
                            if system.isScanning {
                                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                            }
                            Text(T("重新扫描", "Rescan")).font(.system(size: 10))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(system.isScanning)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 216)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        let isSelected = selection == item
        return Button(action: { selection = item }) {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundColor(isSelected ? .white : .secondary)
                Text(item.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .padding(.horizontal, 8)
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
        case .battery: BatteryView()
        case .loadTest: LoadTestView()
        case .power: PowerView()
        case .peripherals: PeripheralsView()
        case .comparison: ComparisonView()
        case .about: AboutView()
        }
    }
}

/// 统一的内容容器：滚动 + 内边距
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
