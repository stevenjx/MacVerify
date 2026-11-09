// Views/HardwareView.swift
//
// 设备信息：机身一张横卡（三列事实），处理器与系统并排。
// 改造前三张卡各占一屏，每张只有 4–7 行，右侧全是空白。
import SwiftUI

struct HardwareView: View {
    @EnvironmentObject private var system: SystemInfoStore

    private var info: MacSystemInfo { system.info }

    private var chassisFacts: [Fact] {
        [
            Fact(T("营销名称", "Marketing name"), info.modelDisplayName),
            Fact(T("机型标识", "Model identifier"), info.modelIdentifier, mono: true),
            Fact(T("机壳型号", "Chassis model"), info.modelNumber.isEmpty ? "—" : info.modelNumber, mono: true),
            Fact(T("配置编号", "Part number"), info.partNumber.isEmpty ? "—" : info.partNumber, mono: true),
            Fact(T("序列号", "Serial number"), info.serialNumber, mono: true),
            Fact(T("架构", "Architecture"), info.architecture),
            Fact(T("出厂年份", "Year"), yearFromModel(info.modelDisplayName)),
            Fact(T("芯片", "Chip"), info.chipName)
        ]
    }

    private var processorFacts: [Fact] {
        [
            Fact(T("核心", "Cores"), coreDescription),
            Fact(T("内存", "Memory"), info.memoryGB > 0 ? "\(info.memoryGB) GB" : "—")
        ] + gpuFacts + [
            Fact(T("存储", "Storage"),
                 info.storage.marketingCapacity == "—"
                    ? info.storage.deviceName
                    : "\(info.storage.marketingCapacity) · \(info.storage.deviceName)")
        ]
    }

    private var systemFacts: [Fact] {
        [
            Fact(T("macOS 版本", "macOS"), info.osVersion),
            Fact(T("系统构建号", "Build"), info.osBuild, mono: true),
            Fact(T("启动时间", "Uptime"), info.systemUptimeText),
            Fact(T("低电量模式", "Low Power Mode"), info.isLowPowerMode ? T("已开启", "On") : T("已关闭", "Off"))
        ]
    }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("设备信息", "Device"),
                subtitle: T("型号、芯片、内存与系统版本", "Model, chip, memory and OS"),
                trailing: AnyView(
                    SecondaryButton(title: T("重新读取", "Reload"), icon: "arrow.clockwise") { system.refresh() }
                )
            )

            Card(title: T("机身与芯片", "Chassis & chip"), icon: "laptopcomputer") {
                FactGrid(facts: chassisFacts, columns: 2, labelWidth: 84)
            }

            HStack(alignment: .top, spacing: Metrics.pageGap) {
                Card(title: T("处理器与内存", "Processor & memory"), icon: "cpu") {
                    FactGrid(facts: processorFacts, columns: 1, labelWidth: 92)
                }

                Card(title: T("系统", "System"), icon: "gearshape") {
                    FactGrid(facts: systemFacts, columns: 1, labelWidth: 92)
                }
            }
        }
    }

    private var coreDescription: String {
        if info.performanceCores > 0 && info.efficiencyCores > 0 {
            // Apple Silicon：物理核就是性能核 + 能效核，没有超线程
            let total = info.performanceCores + info.efficiencyCores
            return T("\(total) 核（\(info.performanceCores) 性能 + \(info.efficiencyCores) 能效）",
                     "\(total) cores (\(info.performanceCores)P + \(info.efficiencyCores)E)")
        }
        if info.logicalCores > info.physicalCores {
            // Intel 超线程：4 核 8 线程
            return T("\(info.physicalCores) 核 \(info.logicalCores) 线程",
                     "\(info.physicalCores) cores, \(info.logicalCores) threads")
        }
        return T("\(info.physicalCores) 核", "\(info.physicalCores) cores")
    }

    /// GPU 一行一块：Intel 机型的核显和 AMD 独显都要出现，不能只显示第一块。
    private var gpuFacts: [Fact] {
        guard !info.gpus.isEmpty else {
            return [Fact(T("图形处理器", "Graphics"), info.gpuName)]
        }
        return info.gpus.enumerated().map { index, gpu in
            let label: String
            if index == 0 {
                label = T("图形处理器", "Graphics")
            } else {
                label = gpu.isBuiltin ? T("集成显卡", "Integrated") : T("独立显卡", "Discrete")
            }
            return Fact(label, gpuText(gpu))
        }
    }

    private func gpuText(_ gpu: GPUInfo) -> String {
        if gpu.cores > 0 {
            return T("\(gpu.name) · \(gpu.cores) 核", "\(gpu.name) · \(gpu.cores) cores")
        }
        if !gpu.bus.isEmpty {
            return gpu.isBuiltin
                ? T("\(gpu.name)（集成）", "\(gpu.name) (integrated)")
                : T("\(gpu.name)（独立）", "\(gpu.name) (discrete)")
        }
        return gpu.name
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
