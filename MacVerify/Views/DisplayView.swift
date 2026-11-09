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

    /// EIZO Monitor Test 的测试项清单：编号 + 名称，和全屏里看到的顺序完全一致
    private var screenTestCard: some View {
        Card(title: T("屏幕检查", "Screen tests"), icon: "rectangle.on.rectangle") {
            VStack(alignment: .leading, spacing: Space.md) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.lg),
                                    GridItem(.flexible(), spacing: Space.lg)],
                          alignment: .leading, spacing: 6) {
                    ForEach(PanelTestSuite.steps()) { step in
                        HStack(spacing: Space.sm) {
                            Text(String(format: "%02d", step.number))
                                .font(Typo.mono)
                                .foregroundColor(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            Text(step.title)
                                .font(Typo.body)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }

                Rectangle().fill(Surface.hairline).frame(height: 1)

                HStack(alignment: .center, spacing: Space.lg) {
                    Text(T("全屏逐项检查：调高亮度、关闭原彩显示与环境光自适应。圆要正、线要直、灰阶不跳变、白底无暗点、黑底无亮点。",
                           "Full-screen checks: raise brightness and turn off True Tone and ambient adaptation. Circles should be round, lines straight, gradients smooth, white free of dead pixels, black free of bright ones."))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.md)
                    PrimaryButton(title: T("开始全屏检查", "Start full-screen test"), icon: "play.fill",
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

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("显示屏", "Display"),
                subtitle: T("面板参数、EDID 指纹与 14 项全屏屏幕检查", "Panel specs, EDID fingerprint and 14 full-screen tests")
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
                    // 机型图代替原来的尺寸环；尺寸挪到右侧文字第一行
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Surface.well)
                        if let imageName = MacModelCatalog.imageName(for: system.info.modelIdentifier) {
                            Image(imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(8)
                        } else {
                            Image(systemName: "laptopcomputer")
                                .font(Typo.icon(28, weight: .light))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 152, height: 94)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(T("机型示意图", "Model artwork"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.inches > 0 ? display.inchText : "—")
                            .font(Typo.metric)
                            .lineLimit(1)
                        Text(display.resolutionText)
                            .font(Typo.title)
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

            screenTestCard
        }
        .onAppear {
            // 自动化核验入口：MACVERIFY_PANEL_TEST=<index> 直接进入全屏检查并停在该项
            guard let raw = ProcessInfo.processInfo.environment["MACVERIFY_PANEL_TEST"],
                  !isPanelTestRunning else { return }
            let index = Int(raw) ?? 0
            isPanelTestRunning = true
            PanelTestController.shared.start(startIndex: index) {
                isPanelTestRunning = false
            }
        }
    }
}
