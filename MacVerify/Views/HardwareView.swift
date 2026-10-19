// Views/HardwareView.swift
import SwiftUI

struct HardwareView: View {
    @EnvironmentObject private var system: SystemInfoStore

    private var info: MacSystemInfo { system.info }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("设备信息", "Device"),
                subtitle: T("型号、芯片、内存与系统版本", "Model, chip, memory and OS"),
                trailing: AnyView(
                    SecondaryButton(title: T("重新读取", "Reload"), icon: "arrow.clockwise") { system.refresh() }
                )
            )

            Card {
                VStack(spacing: 0) {
                    SectionHeader(title: T("机身", "CHASSIS")).padding(.bottom, 8)
                    InfoRow(label: T("机型标识", "Model identifier"), value: info.modelIdentifier, monospaced: true)
                    InfoRow(label: T("营销名称", "Marketing name"), value: info.modelDisplayName)
                    InfoRow(label: T("机型编号", "Model number"), value: info.modelNumber.isEmpty ? "—" : info.modelNumber, monospaced: true)
                    InfoRow(label: T("序列号", "Serial number"), value: info.serialNumber, monospaced: true)
                    InfoRow(label: T("架构", "Architecture"), value: info.architecture)
                    InfoRow(label: T("出厂年份", "Year"), value: yearFromModel(info.modelDisplayName), isLast: true)
                }
            }

            Card {
                VStack(spacing: 0) {
                    SectionHeader(title: T("处理器与内存", "PROCESSOR & MEMORY")).padding(.bottom, 8)
                    InfoRow(label: T("芯片", "Chip"), value: info.chipName)
                    InfoRow(label: T("核心", "Cores"), value: coreDescription)
                    InfoRow(label: T("内存", "Memory"), value: info.memoryGB > 0 ? "\(info.memoryGB) GB" : "—")
                    InfoRow(label: T("图形处理器", "Graphics"), value: info.gpuName, isLast: true)
                }
            }

            Card {
                VStack(spacing: 0) {
                    SectionHeader(title: T("系统", "SYSTEM")).padding(.bottom, 8)
                    InfoRow(label: T("macOS 版本", "macOS"), value: info.osVersion)
                    InfoRow(label: T("系统构建号", "Build"), value: info.osBuild, monospaced: true)
                    InfoRow(label: T("启动时间", "Uptime"), value: info.systemUptimeText)
                    InfoRow(label: T("低电量模式", "Low Power Mode"),
                            value: info.isLowPowerMode ? T("已开启", "On") : T("已关闭", "Off"), isLast: true)
                }
            }
        }
    }

    private var coreDescription: String {
        if info.performanceCores > 0 && info.efficiencyCores > 0 {
            return T("\(info.performanceCores) 性能核 + \(info.efficiencyCores) 能效核（共 \(info.logicalCores) 线程）",
                     "\(info.performanceCores)P + \(info.efficiencyCores)E (\(info.logicalCores) threads)")
        }
        return T("\(info.physicalCores) 核 / \(info.logicalCores) 线程",
                 "\(info.physicalCores) cores / \(info.logicalCores) threads")
    }

    private func yearFromModel(_ name: String) -> String {
        // 从营销名中提取 4 位年份，如 "MacBook Pro 14-inch (M3, 2023)"
        let digits = name.components(separatedBy: CharacterSet.decimalDigits.inverted)
        if let year = digits.first(where: { $0.count == 4 && ($0.hasPrefix("20")) }) {
            return year
        }
        return "—"
    }
}
