// Views/PeripheralsView.swift
//
// F-01 / F-02 / F-03 的界面：无线、摄像头与音频、USB 与雷雳。
// 每条都注明数据从哪来；取不到时显示「不可用」，与报告口径一致。
// 无线与影音并排，总线单独一行，避免三个竖排卡片把页面拉得很长。
import SwiftUI

struct PeripheralsView: View {
    @EnvironmentObject private var system: SystemInfoStore

    private var p: PeripheralsInfo { system.info.peripherals }

    private var wirelessFacts: [Fact] {
        var facts: [Fact] = [
            Fact(T("Wi-Fi 硬件", "Wi-Fi"),
                 p.wifi.scanAvailable ? (p.wifi.isPresent ? T("存在", "Present") : T("不存在", "Absent"))
                                      : T("不可用", "Unavailable"),
                 state: p.wifi.scanAvailable ? (p.wifi.isPresent ? .normal : .absent) : .unavailable)
        ]
        if !p.wifi.bsdDevice.isEmpty {
            facts.append(Fact(T("接口", "Interface"), p.wifi.bsdDevice, mono: true))
        }
        if !p.wifi.chipset.isEmpty {
            facts.append(Fact(T("芯片", "Chipset"), p.wifi.chipset, mono: true))
        }
        if !p.wifi.macSuffix.isEmpty {
            facts.append(Fact(T("MAC 后四位", "MAC suffix"), p.wifi.macSuffix, mono: true))
        }
        facts.append(Fact(T("蓝牙硬件", "Bluetooth"),
                          p.bluetooth.isPresent ? T("存在", "Present") : T("不存在", "Absent")))
        if p.bluetooth.isPresent {
            facts.append(Fact(T("蓝牙芯片", "BT chipset"), p.bluetooth.chipset, mono: true))
            facts.append(Fact(T("总线", "Transport"), p.bluetooth.transport))
            facts.append(Fact(T("固件", "Firmware"), p.bluetooth.firmwareVersion, mono: true))
        }
        return facts
    }

    private var audioFacts: [Fact] {
        var facts: [Fact] = [
            Fact(T("摄像头", "Camera"),
                 p.camera.isPresent ? p.camera.names.joined(separator: " / ") : T("未检测到", "None"),
                 state: p.camera.isPresent ? .normal : .absent),
            Fact(T("内建麦克风", "Built-in mic"),
                 p.audioScanAvailable
                    ? (p.builtinMicrophone.map { T("\($0.inputChannels) 声道", "\($0.inputChannels) ch") } ?? T("未检测到", "None"))
                    : T("不可用", "Unavailable"),
                 state: p.audioScanAvailable ? (p.builtinMicrophone == nil ? .absent : .normal) : .unavailable),
            Fact(T("内建扬声器", "Built-in speaker"),
                 p.audioScanAvailable
                    ? (p.builtinSpeaker.map { T("\($0.outputChannels) 声道", "\($0.outputChannels) ch") } ?? T("未检测到", "None"))
                    : T("不可用", "Unavailable"),
                 state: p.audioScanAvailable ? (p.builtinSpeaker == nil ? .absent : .normal) : .unavailable)
        ]
        let external = p.audio.filter { !$0.isBuiltin }
        if !external.isEmpty {
            facts.append(Fact(T("其他音频设备", "Other audio"), external.map(\.name).joined(separator: " / ")))
        }
        if let peak = p.audio.map(\.sampleRate).max(), peak > 0 {
            facts.append(Fact(T("最高采样率", "Max sample rate"), "\(peak / 1000) kHz"))
        }
        return facts
    }

    private var usbCountText: String {
        guard p.usbScanAvailable else { return T("不可用", "Unavailable") }
        return "\(p.usbDevices.count)"
    }

    private var portFacts: [Fact] {
        var facts: [Fact] = [Fact(T("USB 设备", "USB devices"), usbCountText,
                                 state: p.usbScanAvailable ? .normal : .unavailable)]
        if p.thunderboltScanAvailable {
            let ports = p.thunderboltBuses.reduce(0) { $0 + $1.receptacleStatus.count }
            let used = p.thunderboltBuses.flatMap(\.receptacleStatus)
                .filter { $0 != "receptacle_no_devices_connected" }.count
            facts.append(Fact(T("雷雳口", "Thunderbolt ports"), "\(ports)"))
            facts.append(Fact(T("已连接", "In use"), "\(used)"))
        } else {
            facts.append(Fact(T("雷雳口", "Thunderbolt ports"), T("不可用", "Unavailable"), state: .unavailable))
        }
        return facts
    }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("外设", "Peripherals"),
                subtitle: T("无线、摄像头与音频、USB 与雷雳的实测结果",
                            "Wireless, camera and audio, USB and Thunderbolt as reported by this Mac")
            )

            Card(title: T("无线与影音", "Wireless & audio"), icon: "wifi") {
                HStack(alignment: .top, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.sm) {
                            SectionHeader(title: T("无线", "WIRELESS"))
                            Spacer(minLength: 0)
                            StatusBadge(
                                text: p.wifi.isPresent || p.bluetooth.isPresent
                                    ? T("已检测到", "Detected") : T("未检测到", "Not found"),
                                level: p.wifi.isPresent || p.bluetooth.isPresent ? .ok : .warning
                            )
                        }
                        FactGrid(facts: wirelessFacts, columns: 1, labelWidth: 92)
                    }

                    Rectangle().fill(Surface.hairline).frame(width: 1)

                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.sm) {
                            SectionHeader(title: T("摄像头与音频", "CAMERA & AUDIO"))
                            Spacer(minLength: 0)
                            StatusBadge(
                                text: p.camera.isPresent && p.builtinMicrophone != nil && p.builtinSpeaker != nil
                                    ? T("齐全", "All present") : T("有缺失", "Something missing"),
                                level: p.camera.isPresent && p.builtinMicrophone != nil && p.builtinSpeaker != nil ? .ok : .warning
                            )
                        }
                        FactGrid(facts: audioFacts, columns: 1, labelWidth: 92)
                    }
                }
            }

            Card(title: T("总线与接口", "Buses & ports"), icon: "cable.connector") {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: Space.sm) {
                        ForEach(Array(portFacts.enumerated()), id: \.offset) { _, fact in
                            StatTile(title: fact.label,
                                     value: fact.value,
                                     color: fact.state == .normal ? .secondary : StatusPalette.neutral,
                                     icon: "cable.connector")
                        }
                    }

                    if p.usbScanAvailable && !p.usbDevices.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(p.usbDevices.enumerated()), id: \.offset) { index, device in
                                InfoRow(label: device.name,
                                        value: device.speed.isEmpty ? device.vendor : "\(device.vendor) · \(device.speed)",
                                        isLast: index == p.usbDevices.count - 1)
                            }
                        }
                    } else {
                        Text(p.usbScanAvailable
                             ? T("USB 列表为空表示当前没有连接设备。", "An empty USB list means nothing is connected.")
                             : T("未能读取 USB 设备树。", "The USB device tree could not be read."))
                            .font(Typo.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            NoticeBar(
                text: T("Wi-Fi 走 hardware ports 表 + IORegistry 芯片号；蓝牙、摄像头、音频、USB、雷雳走一次 system_profiler 调用。MAC 只保留后两组数字。",
                       "Wi-Fi comes from the hardware ports table plus the IORegistry chip id; Bluetooth, camera, audio, USB and Thunderbolt come from a single system_profiler call. Only the last two MAC octets are kept."),
                level: .neutral
            )
        }
    }
}
