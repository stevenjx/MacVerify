// Views/DisplayView.swift
//
// 显示屏页：左边一块屏的「主参数」，右边面板信息，身份与检查各占一行。
// 改造前是「一个竖长卡片（下半截空）+ 一张横卡」，两块高度对不齐。
import SwiftUI

struct DisplayView: View {
    @EnvironmentObject private var system: SystemInfoStore
    @State private var isPanelTestRunning = false

    private var display: DisplayInfo { system.info.display }

    private var panelFacts: [Fact] {
        var facts: [Fact] = [
            Fact(T("名称", "Name"), display.name),
            Fact(T("内建屏幕", "Built-in"), display.isBuiltin ? T("是", "Yes") : T("否（外接）", "No (external)")),
            Fact(T("色彩配置", "Colour profile"), display.colorSpaceName)
        ]
        if let panel = display.panel, !panel.typeName.isEmpty {
            facts.append(Fact(T("面板类型", "Panel type"), panel.typeName))
            facts.append(Fact(T("连接方式", "Connection"),
                              panel.connectionType.isEmpty ? "—" : panel.connectionType))
        }
        return facts
    }

    private var identityFacts: [Fact] {
        if let panel = display.panel {
            return [
                Fact(T("面板厂商", "Vendor"), panel.vendorText, mono: true),
                Fact(T("面板型号", "Product"), panel.productText, mono: true),
                Fact(T("面板序列号", "Serial"), panel.serialText, mono: true),
                Fact(T("生产批次", "Production"), panel.productionText, mono: true),
                Fact(T("显示器 ID", "Display ID"),
                     String(format: "0x%04X / 0x%04X", display.vendorID, display.modelID), mono: true)
            ]
        }
        if display.edid != nil {
            return [
                Fact(T("面板厂商代码", "Vendor code"), display.edidManufacturerText, mono: true),
                Fact(T("面板型号代码", "Product code"),
                     String(format: "0x%04X", display.edid!.productCode), mono: true),
                Fact(T("面板序列号", "Serial"), display.edidSerialText, mono: true),
                Fact(T("生产批次", "Production"), display.edidProductionText, mono: true),
                Fact(T("显示器 ID", "Display ID"),
                     String(format: "0x%04X / 0x%04X", display.vendorID, display.modelID), mono: true)
            ]
        }
        return [Fact(T("显示器 ID", "Display ID"),
                     String(format: "0x%04X / 0x%04X", display.vendorID, display.modelID), mono: true)]
    }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("显示屏", "Display"),
                subtitle: T("面板参数、EDID 指纹与纯色检查", "Panel specs, EDID fingerprint and solid-colour test")
            )

            Card(title: T("屏幕", "Display"), icon: "display",
                 trailing: AnyView(
                    Group {
                        if display.edid == nil && display.panel == nil {
                            StatusBadge(text: T("面板身份不可读", "Panel identity unavailable"), level: .neutral)
                        }
                    }
                 )) {
                HStack(alignment: .center, spacing: Space.xl) {
                    RingGauge(
                        title: T("对角线", "Diagonal"),
                        value: display.inches,
                        total: 20,
                        unit: "″",
                        color: .accentColor,
                        size: 82
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(display.resolutionText)
                            .font(Typo.metric)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(display.refreshRate > 0
                             ? String(format: "%.0f Hz · %.0fx", display.refreshRate, display.scale)
                             : "—")
                            .font(Typo.caption)
                            .foregroundColor(.secondary)
                        Text(display.isBuiltin ? T("内建屏幕", "Built-in") : T("外接显示器", "External"))
                            .font(Typo.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 150, alignment: .leading)

                    Rectangle().fill(Surface.hairline).frame(width: 1, height: 62)

                    FactGrid(facts: panelFacts, columns: 2, labelWidth: 76)
                }
            }

            Card(title: T("面板身份", "Panel identity"), icon: "number") {
                VStack(alignment: .leading, spacing: Space.sm) {
                    FactGrid(facts: identityFacts, columns: 3)
                    if display.panel == nil && display.edid == nil {
                        NoticeBar(
                            text: T("本机未向用户态提供面板身份信息，无法据此判断面板来源，请结合外观与显示效果检查。",
                                   "Panel identity is not exposed on this Mac — judge the panel by visual inspection instead."),
                            level: .neutral
                        )
                    }
                }
            }

            Card(title: T("纯色检查", "Solid-colour test"), icon: "circle.lefthalf.filled") {
                HStack(alignment: .center, spacing: Space.lg) {
                    Text(T("全屏显示纯黑、5% / 10% 灰与三原色，用于检查漏光、暗斑、色偏和坏点。检查时请调高屏幕亮度，并关闭环境光自适应。",
                           "Shows full-screen black, low grays and RGB primaries to inspect bleed, dark spots, tint and dead pixels. Raise brightness and disable ambient adaptation."))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.md)
                    PrimaryButton(title: T("开始检查", "Start test"), icon: "play.fill",
                                  enabled: !isPanelTestRunning) {
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
