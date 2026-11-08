// Services/PeripheralsService.swift
//
// 外设采集。原则与整机采集一致：只报系统实际给出的值，取不到就标 unavailable。
//
// 数据源选择说明：
// - Wi-Fi 存在性用 `networksetup -listallhardwareports`（约 0.02s）。
//   不用 `system_profiler SPAirPortDataType`：实测它要 3.7s，而且会枚举周边热点，
//   验机只需要知道这台机器有没有这块硬件，不需要邻居的网络。
// - Wi-Fi 芯片型号取 IORegistry 的 AppleBCMWLANCore.ChipSet（实测 4388 → BCM4388）。
// - 蓝牙用 `system_profiler -json SPBluetoothDataType`（约 0.1s），读 controller_properties。
// - 蓝牙/摄像头/音频/USB/雷电合并成**一次** `system_profiler` 调用：实测分 5 次各起一个进程
//   合计要 1.2s 以上，合并后约 0.3s。输出是按数据类型分键的字典。
import Foundation
import IOKit

enum PeripheralsService {

    private static let profilerTypes = [
        "SPBluetoothDataType", "SPCameraDataType", "SPAudioDataType",
        "SPUSBDataType", "SPThunderboltDataType"
    ]

    static func collect() -> PeripheralsInfo {
        var info = PeripheralsInfo()
        let report = profilerReport()

        info.wifi = readWiFi()
        if let section = report["SPBluetoothDataType"] {
            info.bluetooth = readBluetooth(section)
        }
        if let section = report["SPCameraDataType"] {
            info.camera = readCamera(section)
        }
        if let section = report["SPAudioDataType"] {
            readAudio(section, into: &info)
        }
        if let section = report["SPUSBDataType"] {
            readUSB(section, into: &info)
        }
        if let section = report["SPThunderboltDataType"] {
            readThunderbolt(section, into: &info)
        }
        return info
    }

    /// 一次取回全部外设数据类型。缺键说明该系统不支持该类上报，调用方据此标 unavailable。
    private static func profilerReport() -> [String: [[String: Any]]] {
        guard let output = Shell.run("/usr/sbin/system_profiler", ["-json"] + profilerTypes, timeout: 10),
              let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: [[String: Any]]] = [:]
        for type in profilerTypes {
            if let array = root[type] as? [[String: Any]] {
                result[type] = array
            }
        }
        return result
    }

    // MARK: - F-01 Wi-Fi

    private static func readWiFi() -> WiFiInfo {
        var wifi = WiFiInfo()
        guard let output = Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"]) else {
            return wifi
        }
        wifi.scanAvailable = true

        // 输出按空行分块，每块形如：
        //   Hardware Port: Wi-Fi
        //   Device: en0
        //   Ethernet Address: 5c:e9:1e:b5:50:91
        let blocks = output.components(separatedBy: "\n\n")
        for block in blocks {
            var port: String?
            var device: String?
            var mac: String?
            for line in block.split(separator: "\n") {
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("Hardware Port:") {
                    port = String(text.dropFirst("Hardware Port:".count)).trimmingCharacters(in: .whitespaces)
                } else if text.hasPrefix("Device:") {
                    device = String(text.dropFirst("Device:".count)).trimmingCharacters(in: .whitespaces)
                } else if text.hasPrefix("Ethernet Address:") {
                    mac = String(text.dropFirst("Ethernet Address:".count)).trimmingCharacters(in: .whitespaces)
                }
            }
            guard let portName = port, portName == "Wi-Fi" else { continue }
            wifi.isPresent = true
            wifi.hardwarePort = portName
            wifi.bsdDevice = device ?? ""
            // 只保留 MAC 的后两组（如 50:91）：完整 MAC 是设备标识，
            // 验机时够人工核对即可，不入库。
            if let mac = mac {
                let groups = mac.split(separator: ":")
                if groups.count >= 2 {
                    wifi.macSuffix = groups.suffix(2).joined(separator: ":").uppercased()
                }
            }
            break
        }

        let chip = wifiChipIdentity()
        wifi.chipset = chip.chipset
        wifi.firmwareVersion = chip.firmware
        if !chip.chipset.isEmpty || !chip.firmware.isEmpty {
            wifi.isPresent = true
        }
        return wifi
    }

    /// 无线芯片身份。两条通路覆盖两种平台：
    /// - Intel：传统 kext，类是 IO80211Controller 的子类，可直接按类匹配；
    /// - Apple Silicon：DriverKit 服务，节点类是 IOUserService，
    ///   按类名匹配不到（实测 count = 0），只能遍历后用固件串 "wl0:" 认出无线那一颗。
    private static func wifiChipIdentity() -> (chipset: String, firmware: String) {
        var chipset = ""
        var firmware = ""

        IOKit.forEachService(matching: "IO80211Controller") { service in
            guard chipset.isEmpty else { return }
            if let chip = IOKit.property(service, "ChipSet") as? Int, chip > 0 {
                chipset = "BCM\(chip)"
            }
            if let fw = IOKit.property(service, "FirmwareVersion") as? String, !fw.isEmpty {
                firmware = fw
            }
        }
        if !chipset.isEmpty || !firmware.isEmpty { return (chipset, firmware) }

        IOKit.forEachService(matching: "IOUserService") { service in
            guard chipset.isEmpty, firmware.isEmpty else { return }
            guard let fw = IOKit.property(service, "FirmwareVersion") as? String,
                  fw.hasPrefix("wl0:") else { return }
            firmware = fw
            if let chip = IOKit.property(service, "ChipSet") as? Int, chip > 0 {
                chipset = "BCM\(chip)"
            }
        }
        return (chipset, firmware)
    }

    // MARK: - F-01 蓝牙

    private static func readBluetooth(_ report: [[String: Any]]) -> BluetoothInfo {
        var bluetooth = BluetoothInfo()
        guard let root = report.first,
              let controller = root["controller_properties"] as? [String: Any] else {
            return bluetooth
        }
        bluetooth.isPresent = true
        bluetooth.chipset = controller["controller_chipset"] as? String ?? ""
        bluetooth.vendor = controller["controller_vendorID"] as? String ?? ""
        bluetooth.transport = controller["controller_transport"] as? String ?? ""
        bluetooth.firmwareVersion = controller["controller_firmwareVersion"] as? String ?? ""
        return bluetooth
    }

    // MARK: - F-02 摄像头

    private static func readCamera(_ report: [[String: Any]]) -> CameraInfo {
        var camera = CameraInfo()
        guard !report.isEmpty else { return camera }
        camera.isPresent = true
        for entry in report {
            // 名称随系统语言变化（中文系统是「FaceTime高清相机」），只作为展示，不用来判定。
            if let model = entry["spcamera_model-id"] as? String, !model.isEmpty {
                camera.names.append(model)
            }
        }
        return camera
    }

    // MARK: - F-02 音频

    /// 音频设备。`coreaudio_device_transport` 为 builtin 时才是内建，
    /// 因此「内建麦克风 / 内建扬声器」这一判断有据可依，不是靠名字猜。
    private static func readAudio(_ report: [[String: Any]], into info: inout PeripheralsInfo) {
        guard !report.isEmpty else { return }
        info.audioScanAvailable = true
        for block in report {
            guard let items = block["_items"] as? [[String: Any]] else { continue }
            for item in items {
                guard let name = item["_name"] as? String else { continue }
                info.audio.append(AudioPeripheral(
                    name: name,
                    transport: item["coreaudio_device_transport"] as? String ?? "",
                    inputChannels: item["coreaudio_device_input"] as? Int ?? 0,
                    outputChannels: item["coreaudio_device_output"] as? Int ?? 0,
                    sampleRate: item["coreaudio_device_srate"] as? Int ?? 0
                ))
            }
        }
    }

    // MARK: - F-03 USB

    /// USB 设备树。系统会把设备嵌套在 `_items` 里（集线器下面挂设备），需要递归。
    /// 数组为空表示「当前没有连接 USB 设备」，不是读不到——两者含义不同。
    static func readUSB(_ report: [[String: Any]], into info: inout PeripheralsInfo) {
        info.usbScanAvailable = true
        var collected: [USBDevice] = []
        func walk(_ nodes: [[String: Any]]) {
            for node in nodes {
                let name = (node["_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                // 总线本身不是设备：系统会给总线节点一个 "host_controller" 或 "pci_device" 标记
                let isBus = node["host_controller"] != nil || node["pci_device"] != nil
                if !name.isEmpty, !isBus {
                    collected.append(USBDevice(
                        name: name,
                        vendor: firstString(node, ["manufacturer", "vendor_name", "USB Vendor Name"]),
                        speed: firstString(node, ["link_speed", "device_speed", "USB Device Speed"]),
                        serialNumber: firstString(node, ["serial_num", "USB Serial Number"])
                    ))
                }
                if let children = node["_items"] as? [[String: Any]] {
                    walk(children)
                }
            }
        }
        walk(report)
        info.usbDevices = collected
    }

    /// 同一个含义在不同系统版本里可能换键名，按候选顺序取第一个非空值。
    private static func firstString(_ node: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            if let value = node[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    // MARK: - F-03 Thunderbolt

    static func readThunderbolt(_ report: [[String: Any]], into info: inout PeripheralsInfo) {
        info.thunderboltScanAvailable = true
        info.thunderboltBuses = report.map { bus in
            var statuses: [String] = []
            var speed = ""
            // 每个口一个 receptacle_N_tag
            for key in bus.keys.sorted() where key.hasPrefix("receptacle") && key.hasSuffix("_tag") {
                guard let tag = bus[key] as? [String: Any] else { continue }
                let status = tag["receptacle_status_key"] as? String ?? ""
                statuses.append(status)
                if speed.isEmpty {
                    speed = tag["current_speed_key"] as? String ?? ""
                }
            }
            return ThunderboltBus(
                name: bus["_name"] as? String ?? "—",
                receptacleStatus: statuses,
                speed: speed
            )
        }
    }

    // MARK: - 公共
}
