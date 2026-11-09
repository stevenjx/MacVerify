// Views/PortTestView.swift
//
// 接口测试：逐个接口插入设备，实时显示接入/拔出事件与链路速率。
// 枚举走 IOKit（USB / 雷雳 / 外置存储），每秒与上一帧做差分，不依赖轮询 system_profiler。
import SwiftUI
import IOKit
import IOKit.usb

// MARK: - 监视器

@MainActor
final class PortMonitor: ObservableObject {
    struct Event: Identifiable {
        let id = UUID()
        let time: String
        let inserted: Bool
        let name: String
        let detail: String
    }

    struct Device: Identifiable {
        let id: String
        let name: String
        let detail: String
    }

    @Published var events: [Event] = []
    @Published var devices: [Device] = []
    @Published var isMonitoring = false
    @Published var enumerationAvailable = true

    private var previous: Set<String> = []
    private var timer: Timer?

    var insertCount: Int { events.filter(\.inserted).count }

    func refreshDevices() {
        let now = Self.enumerate()
        devices = now.map { Device(id: $0.key, name: $0.name, detail: $0.detail) }
        enumerationAvailable = !now.isEmpty || !isMonitoring
    }

    func start() {
        guard timer == nil else { return }
        let now = Self.enumerate()
        previous = Set(now.map(\.key))
        devices = now.map { Device(id: $0.key, name: $0.name, detail: $0.detail) }
        isMonitoring = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    func clearEvents() {
        events.removeAll()
    }

    private func tick() {
        let now = Self.enumerate()
        let keys = Set(now.map(\.key))

        for item in now where !previous.contains(item.key) {
            events.insert(Event(time: Self.timestamp(), inserted: true, name: item.name, detail: item.detail), at: 0)
        }
        for key in previous.subtracting(keys) {
            let name = key.components(separatedBy: "|").first ?? key
            events.insert(Event(time: Self.timestamp(), inserted: false, name: name, detail: ""), at: 0)
        }

        previous = keys
        devices = now.map { Device(id: $0.key, name: $0.name, detail: $0.detail) }
    }

    // MARK: - 枚举

    private struct Found { let key: String; let name: String; let detail: String }

    private static func enumerate() -> [Found] {
        usbDevices() + thunderboltDevices() + externalDisks()
    }

    private static func forEachService(_ className: String, _ body: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching(className),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            body(service)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private static func usbDevices() -> [Found] {
        var result: [Found] = []
        forEachService("IOUSBHostDevice") { service in
            guard let name = stringProp(service, "USB Product Name") ?? registryName(service),
                  !name.isEmpty else { return }
            let speed = speedLabel(intProp(service, "Device Speed"))
            let location = intProp(service, "locationID") ?? 0
            result.append(Found(key: "\(name)|usb\(location)", name: name, detail: speed))
        }
        return result
    }

    /// 雷雳设备走 PCIe 隧道，不会出现在 USB 树里；根交换机 Depth = 0，只取 Depth ≥ 1
    private static func thunderboltDevices() -> [Found] {
        var result: [Found] = []
        forEachService("IOThunderboltSwitch") { service in
            guard let depth = intProp(service, "Depth"), depth > 0 else { return }
            let vendor = stringProp(service, "Device Vendor Name") ?? ""
            let model = stringProp(service, "Device Model Name") ?? T("雷雳设备", "Thunderbolt device")
            let name = [vendor, model].filter { !$0.isEmpty }.joined(separator: " ")
            let uid = (IORegistryEntryCreateCFProperty(service, "UID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber)?.stringValue ?? name
            result.append(Found(key: "\(name)|tb\(uid)", name: name, detail: "Thunderbolt"))
        }
        return result
    }

    /// 外置磁盘（雷电硬盘盒、SD 卡）。USB 存储已由 USB 树覆盖，这里跳过避免重复计数。
    private static func externalDisks() -> [Found] {
        var result: [Found] = []
        let parents = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        forEachService("IOMedia") { service in
            guard (IORegistryEntryCreateCFProperty(service, "Whole" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Bool) == true,
                  let characteristics = IORegistryEntrySearchCFProperty(
                    service, kIOServicePlane, "Protocol Characteristics" as CFString,
                    kCFAllocatorDefault, parents) as? [String: Any]
            else { return }
            let interconnect = characteristics["Physical Interconnect"] as? String ?? ""
            let location = characteristics["Physical Interconnect Location"] as? String ?? ""
            let isSDCard = interconnect == "Secure Digital"
            guard (location == "External" || isSDCard), interconnect != "USB" else { return }

            let details = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, "Device Characteristics" as CFString,
                kCFAllocatorDefault, parents) as? [String: Any]
            let product = (details?["Product Name"] as? String)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            var name = product.isEmpty ? T("外置存储", "External storage") : product
            if let size = intProp(service, "Size"), size > 0 {
                name += " · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .decimal)
            }
            let bsd = stringProp(service, "BSD Name") ?? name
            let detail = isSDCard ? T("SD 读卡器", "SD reader")
                : (interconnect.isEmpty ? T("外置存储", "External storage") : interconnect)
            result.append(Found(key: "\(name)|disk\(bsd)", name: name, detail: detail))
        }
        return result
    }

    private static func stringProp(_ service: io_service_t, _ key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return value.takeRetainedValue() as? String
    }

    private static func intProp(_ service: io_service_t, _ key: String) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return (value.takeRetainedValue() as? NSNumber)?.intValue
    }

    private static func registryName(_ service: io_service_t) -> String? {
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 128)
        defer { buffer.deallocate() }
        guard IORegistryEntryGetName(service, buffer) == KERN_SUCCESS else { return nil }
        return String(cString: buffer)
    }

    private static func speedLabel(_ speed: Int?) -> String {
        switch speed {
        case 0: return T("USB 1.0 低速", "USB 1.0 low speed")
        case 1: return T("USB 1.1 全速", "USB 1.1 full speed")
        case 2: return T("USB 2.0 高速", "USB 2.0 high speed")
        case 3: return "USB 3 (5 Gbps)"
        case 4: return "USB 3.1 (10 Gbps)"
        case 5: return "USB 3.2 (20 Gbps)"
        default: return T("速率未知", "Speed unknown")
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

// MARK: - 页面

struct PortTestView: View {
    @StateObject private var monitor = PortMonitor()

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("接口测试", "Port Test"),
                subtitle: T("逐个接口插入设备，看是否都能被识别", "Plug a device into each port and watch it get recognized"),
                trailing: AnyView(
                    StatusBadge(text: monitor.isMonitoring ? T("监听中", "Listening") : T("未开始", "Idle"),
                                level: monitor.isMonitoring ? .ok : .neutral)
                )
            )

            Card(title: T("当前连接的设备", "Connected now"), icon: "cable.connector") {
                VStack(alignment: .leading, spacing: 0) {
                    if monitor.devices.isEmpty {
                        Text(T("当前没有检测到 USB / 雷雳 / 外置存储设备。",
                               "No USB, Thunderbolt or external storage devices detected."))
                            .font(Typo.body)
                            .foregroundColor(.secondary)
                            .padding(.vertical, Space.sm)
                    } else {
                        ForEach(monitor.devices) { device in
                            HStack(spacing: Space.sm) {
                                Image(systemName: "externaldrive.connected.to.line.below")
                                    .font(Typo.icon(10))
                                    .foregroundColor(.secondary)
                                Text(device.name).font(Typo.body).lineLimit(1)
                                Spacer(minLength: Space.sm)
                                Text(device.detail).font(Typo.caption).foregroundColor(.secondary)
                            }
                            .frame(height: Metrics.row)
                        }
                    }
                }
            }

            HStack(spacing: Space.sm) {
                if monitor.isMonitoring {
                    SecondaryButton(title: T("停止监听", "Stop"), icon: "stop.fill") { monitor.stop() }
                    SecondaryButton(title: T("清除记录", "Clear log"), icon: "trash") { monitor.clearEvents() }
                } else {
                    PrimaryButton(title: T("开始监听", "Start listening"), icon: "play.fill") { monitor.start() }
                    SecondaryButton(title: T("刷新", "Refresh"), icon: "arrow.clockwise") { monitor.refreshDevices() }
                }
                Spacer(minLength: 0)
                Text(T("已捕获接入 \(monitor.insertCount) 次", "\(monitor.insertCount) connections captured"))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
            }

            Card(title: T("插拔记录", "Plug / unplug log"), icon: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 0) {
                    if monitor.events.isEmpty {
                        Text(T("开始监听后，插入或拔出设备会记录在这里。",
                               "Start listening, then plug or unplug a device to see it here."))
                            .font(Typo.body)
                            .foregroundColor(.secondary)
                            .padding(.vertical, Space.sm)
                    } else {
                        ForEach(monitor.events.prefix(12)) { event in
                            HStack(spacing: Space.sm) {
                                StatusDot(level: event.inserted ? .ok : .neutral, size: 6)
                                Text(event.time).font(Typo.mono).foregroundColor(.secondary)
                                Text(event.inserted ? T("接入", "Connected") : T("拔出", "Removed"))
                                    .font(Typo.bodyStrong)
                                Text(event.name).font(Typo.body).lineLimit(1)
                                Spacer(minLength: Space.sm)
                                if !event.detail.isEmpty {
                                    Text(event.detail).font(Typo.caption).foregroundColor(.secondary)
                                }
                            }
                            .frame(height: Metrics.row)
                        }
                    }
                }
            }

            NoticeBar(text: T("逐个接口插入 U 盘、读卡器或线缆：每插一次都应出现一条「接入」记录。拔掉后如果不出现「拔出」，说明该口的数据线可能有问题。",
                              "Plug a USB drive, card reader or cable into each port: every insertion should log a connection. If unplugging logs nothing, that port's data lines may be faulty."),
                      level: .neutral)
        }
        .onAppear { monitor.refreshDevices() }
        .onDisappear { monitor.stop() }
        .onChange(of: monitor.insertCount) { count in
            // 至少成功识别过一次插入，才说明「能插设备」这件事被验证过
            if count > 0 { TestProgress.shared.markCompleted("ports") }
        }
    }
}
