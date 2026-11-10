// Services/ScanHistory.swift
//
// F-04 两次检测对比：同机不同时间，或两台机器并排。
//
// 做法：每次扫描把「可比字段」存成一份快照（UserDefaults，最多 12 份），
// 之后可以任选两份逐字段比。跨机器对比靠导入对方导出的报告 JSON。
//
// 只存实测值，不存推断结论；字段缺失时值为 "unavailable"，与界面口径一致。
import Foundation
import Combine

struct SnapshotField: Codable, Equatable {
    let key: String
    let label: String
    let value: String
}

struct ScanSnapshot: Codable, Identifiable, Equatable {
    var id = UUID()
    var capturedAt: Date
    /// 来源：本机扫描，或导入的文件名
    var source: String
    var modelName: String
    var serialNumber: String
    var fields: [SnapshotField]
    /// 报告自带的指纹（F-05）。旧快照没有这个字段，因此为可选。
    var fingerprint: String? = nil

    var displayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return "\(formatter.string(from: capturedAt)) · \(modelName)"
    }
}

enum ScanHistoryStore {
    static let storageKey = "macverify.scan.history"
    static let limit = 12

    // 存储实例可注入：App 用标准 UserDefaults，测试用独立 suite。
    // 否则并行跑的用例会互相清库，出现「单跑通过、并行失败」的假象。

    static func load(from store: UserDefaults = .standard) -> [ScanSnapshot] {
        guard let data = store.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([ScanSnapshot].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [ScanSnapshot], to store: UserDefaults = .standard) {
        let trimmed = Array(list.prefix(limit))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        store.set(data, forKey: storageKey)
    }

    /// 会随时间自然漂移的字段。它们变化不代表硬件状态发生了一次有意义的改变，
    /// 判重时忽略，避免每次启动都多存一条几乎一样的记录。
    private static let volatileKeys: Set<String> = [
        "smart_power_on_hours", "smart_power_cycles", "ssd_health",
        "battery_cycle_count", "battery_health", "battery_full_capacity",
        "kernel_panics", "os"
    ]

    /// 两份快照是否描述同一个「硬件状态」：同指纹，且除漂移字段外全部相同。
    static func isSameState(_ a: ScanSnapshot, _ b: ScanSnapshot) -> Bool {
        guard a.fingerprint == b.fingerprint else { return false }
        func stable(_ fields: [SnapshotField]) -> [String: String] {
            var map: [String: String] = [:]
            for field in fields where !volatileKeys.contains(field.key) {
                map[field.key] = field.value
            }
            return map
        }
        return stable(a.fields) == stable(b.fields)
    }

    /// 追加一份快照。与最新一份属于同一硬件状态时替换它，而不是堆一条近重复记录。
    static func append(_ snapshot: ScanSnapshot, to store: UserDefaults = .standard) {
        var list = load(from: store)
        if let newest = list.first, isSameState(newest, snapshot) {
            list[0] = snapshot
        } else {
            list.removeAll { isSameState($0, snapshot) }
            list.insert(snapshot, at: 0)
        }
        save(list, to: store)
    }

    static func clear(_ store: UserDefaults = .standard) {
        store.removeObject(forKey: storageKey)
    }
}

// MARK: - 快照构建

extension ScanSnapshot {

    /// 按快照字段重新算一遍指纹。与 `fingerprint` 不一致，说明报告里的字段被改过。
    var recomputedFingerprint: String {
        var values: [String: String] = [:]
        for field in fields { values[field.key] = field.value }
        return DeviceFingerprint.compute(values)
    }

    /// nil = 报告没带指纹（旧版本或非本工具导出）
    var fingerprintMatches: Bool? {
        guard let stored = fingerprint, !stored.isEmpty else { return nil }
        return stored == recomputedFingerprint
    }

    /// 从本机实测值构建快照。
    /// 直接复用报告 JSON 作为唯一来源：导出口径与对比口径必须是同一套键和同一套格式，
    /// 否则「本机扫描」与「导入的报告」相比会出现一堆假的差异。
    static func make(info: MacSystemInfo, battery: BatterySnapshot, source: String) -> ScanSnapshot {
        if let data = ReportService.json(info: info, battery: battery),
           var snapshot = make(reportJSON: data, source: source) {
            snapshot.capturedAt = info.scannedAt
            return snapshot
        }
        return ScanSnapshot(capturedAt: info.scannedAt, source: source,
                            modelName: info.modelDisplayName,
                            serialNumber: info.serialNumber, fields: [])
    }

    /// 快照字段顺序。键取自报告 JSON，顺序在这里固定，避免字典无序导致每次排列不同。
    private static let orderedKeys: [String] = [
        "model_identifier", "marketing_name", "part_number", "serial_number",
        "chip", "memory", "gpu", "os",
        "storage_model", "storage_capacity", "storage_physical_bytes",
        "ssd_health", "smart_power_on_hours", "smart_power_cycles",
        "smart_unsafe_shutdowns", "smart_media_errors",
        "display_resolution", "display_size", "display_refresh",
        "panel_vendor", "panel_product", "panel_serial", "panel_type",
        "battery_design_capacity", "battery_cycle_count", "battery_health",
        "battery_full_capacity", "battery_serial",
        "activation_lock", "file_vault", "sip", "gatekeeper", "mdm", "kernel_panics",
        "wifi", "wifi_device", "wifi_chipset", "wifi_mac",
        "bluetooth", "bt_chipset", "bt_transport", "bt_firmware",
        "camera", "mic", "speaker",
        "usb", "usb_list", "thunderbolt", "thunderbolt_ports", "thunderbolt_connected"
    ]

    /// 从本 App 导出的报告 JSON 还原快照（用于两台机器并排比较）。
    /// 只认自己写的格式：sections → items → {label, value}。
    static func make(reportJSON data: Data, source: String) -> ScanSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["sections"] as? [String: [String: [String: Any]]],
              root["tool"] as? String == "MacVerify" else { return nil }

        var byKey: [String: String] = [:]
        var labels: [String: String] = [:]
        for (_, items) in sections {
            for (key, item) in items {
                labels[key] = item["label"] as? String ?? key
                if let value = item["value"] as? String, !value.isEmpty {
                    byKey[key] = value
                } else {
                    byKey[key] = "unavailable"
                }
            }
        }

        // 只取白名单里的键：一致性/原装性那些结论行的 key 是本地化标题，
        // 中文报告和英文报告直接比会整片「不同」，没有意义；而且它们本身也不是硬件事实。
        let keys = orderedKeys.filter { labels[$0] != nil }

        let rows = keys.map { key in
            SnapshotField(key: key, label: labels[key] ?? key, value: byKey[key] ?? "unavailable")
        }

        let generated = (root["scanned_at"] as? String) ?? ""
        let parsedDate = ISO8601DateFormatter().date(from: generated) ?? Date()
        let serial = byKey["serial_number"] ?? "unavailable"
        let model = byKey["marketing_name"] ?? byKey["model_identifier"] ?? "—"

        var snapshot = ScanSnapshot(capturedAt: parsedDate, source: source,
                                    modelName: model, serialNumber: serial, fields: rows)
        snapshot.fingerprint = root["fingerprint"] as? String
        return snapshot
    }
}
// MARK: - 差异

struct DiffRow: Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let before: String
    let after: String

    var changed: Bool { before != after }
}

enum SnapshotDiff {
    /// 以 A 为基准（before），B 为对照（after）。
    /// 字段顺序跟随 A 的字段顺序，B 多出来的字段附在末尾。
    static func compare(_ a: ScanSnapshot, _ b: ScanSnapshot) -> [DiffRow] {
        var rows: [DiffRow] = []
        var seen = Set<String>()

        for field in a.fields {
            let other = b.fields.first { $0.key == field.key }
            rows.append(DiffRow(key: field.key, label: field.label,
                                before: field.value, after: other?.value ?? "unavailable"))
            seen.insert(field.key)
        }
        for field in b.fields where !seen.contains(field.key) {
            rows.append(DiffRow(key: field.key, label: field.label,
                                before: "unavailable", after: field.value))
        }
        return rows
    }

    static func changedCount(_ rows: [DiffRow]) -> Int {
        rows.filter(\.changed).count
    }
}
