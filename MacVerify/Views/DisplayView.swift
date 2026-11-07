// Views/DisplayView.swift
import SwiftUI

struct DisplayView: View {
    @EnvironmentObject private var system: SystemInfoStore
    @State private var isPanelTestRunning = false

    private var display: DisplayInfo { system.info.display }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("显示屏", "Display"),
                subtitle: T("面板参数、EDID 指纹与纯色检查", "Panel specs, EDID fingerprint and solid-colour test")
            )

            HStack(alignment: .top, spacing: 16) {
                Card {
                    VStack(spacing: 12) {
                        RingGauge(
                            title: T("屏幕尺寸", "Screen size"),
                            value: display.inches,
                            total: 20,
                            unit: "″",
                            color: .accentColor,
                            caption: display.isBuiltin ? T("内建屏幕", "Built-in") : T("外接显示器", "External")
                        )
                        VStack(spacing: 2) {
                            Text(display.resolutionText)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            Text(display.refreshRate > 0 ? String(format: "%.0f Hz", display.refreshRate) : "—")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 168)
                    .padding(.vertical, 8)
                }
                .frame(width: 200)

                Card {
                    VStack(spacing: 0) {
                        SectionHeader(title: T("面板", "PANEL")).padding(.bottom, 8)
                        InfoRow(label: T("名称", "Name"), value: display.name)
                        InfoRow(label: T("分辨率", "Resolution"), value: display.resolutionText, monospaced: true)
                        InfoRow(label: T("刷新率", "Refresh rate"), value: display.refreshRate > 0 ? String(format: "%.0f Hz", display.refreshRate) : "—")
                        InfoRow(label: T("缩放倍率", "Scale"), value: display.scale > 0 ? String(format: "%.1fx", display.scale) : "—")
                        InfoRow(label: T("内建屏幕", "Built-in"), value: display.isBuiltin ? T("是", "Yes") : T("否（外接）", "No (external)"))
                        InfoRow(label: T("色彩配置", "Colour profile"), value: display.colorSpaceName, isLast: true)
                    }
                }
            }

            Card {
                VStack(spacing: 0) {
                    HStack {
                        SectionHeader(title: T("面板身份", "PANEL IDENTITY"))
                        Spacer()
                        if display.edid == nil && display.panel == nil {
                            StatusBadge(text: T("无法读取", "Unavailable"), level: .neutral)
                        }
                    }
                    .padding(.bottom, 8)

                    if let panel = display.panel {
                        InfoRow(label: T("面板厂商", "Panel vendor"), value: panel.vendorText, monospaced: true)
                        InfoRow(label: T("面板型号", "Panel product"), value: panel.productText, monospaced: true)
                        InfoRow(label: T("面板序列号", "Panel serial"), value: panel.serialText, monospaced: true)
                        if !panel.typeName.isEmpty {
                            InfoRow(label: T("面板类型", "Panel type"), value: panel.typeName)
                        }
                        InfoRow(label: T("连接方式", "Connection"), value: panel.connectionType.isEmpty ? "—" : panel.connectionType)
                        InfoRow(label: T("生产批次", "Production"), value: panel.productionText, monospaced: true)
                        InfoRow(label: T("显示器 ID", "Display ID"),
                                value: String(format: "0x%04X / 0x%04X", display.vendorID, display.modelID),
                                monospaced: true, isLast: true)
                    } else if display.edid != nil {
                        InfoRow(label: T("面板厂商代码", "Manufacturer ID"), value: display.edidManufacturerText, monospaced: true)
                        InfoRow(label: T("面板型号代码", "Product code"), value: String(format: "0x%04X", display.edid!.productCode), monospaced: true)
                        InfoRow(label: T("面板序列号", "Panel serial"), value: display.edidSerialText, monospaced: true)
                        InfoRow(label: T("生产批次", "Production"), value: display.edidProductionText, monospaced: true)
                        InfoRow(label: T("显示器 ID", "Display ID"),
                                value: String(format: "0x%04X / 0x%04X", display.vendorID, display.modelID),
                                monospaced: true, isLast: true)
                    } else {
                        NoticeBar(
                            text: T("本机未向用户态提供面板身份信息，无法据此判断面板来源，请结合外观与显示效果检查。",
                                   "Panel identity is not exposed on this Mac — judge the panel by visual inspection instead."),
                            level: .neutral
                        )
                        .padding(.bottom, 6)
                        InfoRow(label: T("显示器 ID", "Display ID"),
                                value: String(format: "0x%04X / 0x%04X", display.vendorID, display.modelID),
                                monospaced: true, isLast: true)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: T("纯色检查", "SOLID-COLOUR TEST"))
                    Text(T("全屏显示纯黑、5% / 10% 灰与三原色，用于检查漏光、暗斑、色偏和坏点。检查时请调高屏幕亮度，并关闭环境光自适应。",
                           "Shows full-screen black, low grays and RGB primaries to inspect bleed, dark spots, tint and dead pixels. Raise brightness and disable ambient adaptation."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    PrimaryButton(title: T("开始检查", "Start test"), icon: "play.fill", enabled: !isPanelTestRunning) {
                        isPanelTestRunning = true
                        PanelTestController.shared.start {
                            isPanelTestRunning = false
                        }
                    }
                }
            }
        }
    }
}
