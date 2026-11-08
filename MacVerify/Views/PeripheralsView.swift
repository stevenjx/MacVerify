// Views/PeripheralsView.swift
//
// F-01 / F-02 / F-03 的界面：无线、摄像头与音频、USB 与雷雳。
// 每条都注明数据从哪来；取不到时显示「不可用」，与报告口径一致。
import SwiftUI

struct PeripheralsView: View {
    @EnvironmentObject private var system: SystemInfoStore

    private var p: PeripheralsInfo { system.info.peripherals }

    var body: some View {
        PageScroll {
            header
            wifiCard
            audioCard
            busCard
            footnote
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(T("外设", "Peripherals")).font(.system(size: 20, weight: .semibold))
            Text(T("无线、摄像头与音频、USB 与雷雳的实测结果", "Wireless, camera and audio, USB and Thunderbolt as reported by this Mac"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Wi-Fi / 蓝牙

    private var wifiCard: some View {
        Card {
            VStack(spacing: 0) {
                HStack {
                    SectionHeader(title: T("无线", "WIRELESS"))
                    Spacer()
                    StatusBadge(
                        text: p.wifi.isPresent || p.bluetooth.isPresent
                            ? T("已检测到", "Detected") : T("未检测到", "Not found"),
                        level: p.wifi.isPresent || p.bluetooth.isPresent ? .ok : .warning
                    )
                }
                .padding(.bottom, 8)

                InfoRow(label: T("Wi-Fi 硬件", "Wi-Fi hardware"),
                        value: p.wifi.scanAvailable ? (p.wifi.isPresent ? T("存在", "Present") : T("不存在", "Absent")) : T("不可用", "Unavailable"))
                if !p.wifi.bsdDevice.isEmpty {
                    InfoRow(label: T("接口", "Interface"), value: p.wifi.bsdDevice, monospaced: true)
                }
                if !p.wifi.chipset.isEmpty {
                    InfoRow(label: T("芯片", "Chipset"), value: p.wifi.chipset, monospaced: true)
                }
                if !p.wifi.macSuffix.isEmpty {
                    InfoRow(label: T("MAC 后四位", "MAC suffix"), value: p.wifi.macSuffix, monospaced: true)
                }
                InfoRow(label: T("蓝牙硬件", "Bluetooth"),
                        value: p.bluetooth.isPresent ? T("存在", "Present") : T("不存在", "Absent"))
                if p.bluetooth.isPresent {
                    InfoRow(label: T("蓝牙芯片", "BT chipset"), value: p.bluetooth.chipset, monospaced: true)
                    InfoRow(label: T("总线", "Transport"), value: p.bluetooth.transport)
                    InfoRow(label: T("固件", "Firmware"), value: p.bluetooth.firmwareVersion, monospaced: true, isLast: true)
                }
            }
        }
    }

    // MARK: - 摄像头 / 音频

    private var audioCard: some View {
        Card {
            VStack(spacing: 0) {
                HStack {
                    SectionHeader(title: T("摄像头与音频", "CAMERA & AUDIO"))
                    Spacer()
                    StatusBadge(
                        text: p.camera.isPresent && p.builtinMicrophone != nil && p.builtinSpeaker != nil
                            ? T("齐全", "All present") : T("有缺失", "Something missing"),
                        level: p.camera.isPresent && p.builtinMicrophone != nil && p.builtinSpeaker != nil ? .ok : .warning
                    )
                }
                .padding(.bottom, 8)

                InfoRow(label: T("摄像头", "Camera"),
                        value: p.camera.isPresent
                            ? p.camera.names.joined(separator: " / ")
                            : T("未检测到", "None"))
                InfoRow(label: T("内建麦克风", "Built-in mic"),
                        value: p.audioScanAvailable
                            ? (p.builtinMicrophone.map { T("\($0.inputChannels) 声道", "\($0.inputChannels) ch") } ?? T("未检测到", "None"))
                            : T("不可用", "Unavailable"))
                InfoRow(label: T("内建扬声器", "Built-in speaker"),
                        value: p.audioScanAvailable
                            ? (p.builtinSpeaker.map { T("\($0.outputChannels) 声道", "\($0.outputChannels) ch") } ?? T("未检测到", "None"))
                            : T("不可用", "Unavailable"))

                let external = p.audio.filter { !$0.isBuiltin }
                if !external.isEmpty {
                    InfoRow(label: T("其他音频设备", "Other audio"),
                            value: external.map(\.name).joined(separator: " / "))
                }
                if let peak = p.audio.map(\.sampleRate).max(), peak > 0 {
                    InfoRow(label: T("最高采样率", "Max sample rate"),
                            value: "\(peak / 1000) kHz", isLast: true)
                }
            }
        }
    }

    // MARK: - USB / 雷雳

    private var busCard: some View {
        Card {
            VStack(spacing: 0) {
                SectionHeader(title: T("总线与接口", "BUSES & PORTS")).padding(.bottom, 8)

                if !p.usbScanAvailable {
                    InfoRow(label: T("USB", "USB"), value: T("不可用", "Unavailable"))
                } else if p.usbDevices.isEmpty {
                    InfoRow(label: T("USB", "USB"), value: T("当前未连接设备", "No devices connected"))
                } else {
                    InfoRow(label: T("USB 设备", "USB devices"), value: "\(p.usbDevices.count)")
                    ForEach(Array(p.usbDevices.enumerated()), id: \.offset) { _, device in
                        InfoRow(label: device.name,
                                value: device.speed.isEmpty ? device.vendor : "\(device.vendor) · \(device.speed)")
                    }
                }

                if p.thunderboltScanAvailable {
                    let ports = p.thunderboltBuses.reduce(0) { $0 + $1.receptacleStatus.count }
                    let used = p.thunderboltBuses.flatMap(\.receptacleStatus)
                        .filter { $0 != "receptacle_no_devices_connected" }.count
                    InfoRow(label: T("雷雳口", "Thunderbolt ports"), value: "\(ports)")
                    InfoRow(label: T("已连接设备", "Ports in use"), value: "\(used)",
                            isLast: true)
                } else {
                    InfoRow(label: T("雷雳口", "Thunderbolt ports"), value: T("不可用", "Unavailable"), isLast: true)
                }
            }
        }
    }

    private var footnote: some View {
        NoticeBar(
            text: T("Wi-Fi 走 hardware ports 表 + IORegistry 芯片号；蓝牙、摄像头、音频、USB、雷雳走一次 system_profiler 调用。USB 列表为空表示当前没插设备，不是读不到。MAC 只保留后两组数字。",
                   "Wi-Fi comes from the hardware ports table plus the IORegistry chip id; Bluetooth, camera, audio, USB and Thunderbolt come from a single system_profiler call. An empty USB list means nothing is plugged in, not that it is unreadable. Only the last two MAC octets are kept."),
            level: .neutral
        )
    }
}
