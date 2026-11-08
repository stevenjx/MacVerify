// Core/Fingerprint.swift
//
// F-05 报告指纹。
//
// 用途有两个：
// 1. 防换头：两份报告除了序列号以外被互相调换时，指纹会跟着变；
// 2. 防篡改：报告里带上指纹，重新按同一规则算一遍就能看出字段有没有被改过。
//
// 指纹只覆盖「硬件身份」字段，不覆盖时间、版本、结论——那些本来就会变。
// 算法：把这些字段按固定顺序拼成 key=value 行，取 SHA-256 前 16 位十六进制。
import Foundation
import CryptoKit

enum DeviceFingerprint {

    /// 参与指纹的字段。改动这个列表会让历史报告的指纹失效，属于破坏性变更。
    static let identityKeys = [
        "model_identifier", "serial_number", "chip", "memory",
        "storage_physical_bytes", "storage_capacity",
        "panel_product", "panel_serial", "battery_serial"
    ]

    /// 从「key → value」字典取指纹。缺失的字段按 unavailable 参与计算，
    /// 这样同一台机器两次扫描（字段集合相同）结果稳定。
    static func compute(_ values: [String: String]) -> String {
        let canonical = identityKeys
            .map { "\($0)=\(values[$0] ?? "unavailable")" }
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).uppercased()
    }

    /// 短的展示形式，便于人眼核对
    static func display(_ fingerprint: String) -> String {
        guard fingerprint.count == 16 else { return fingerprint.isEmpty ? "—" : fingerprint }
        let mid = fingerprint.index(fingerprint.startIndex, offsetBy: 8)
        return "\(fingerprint[..<mid])-\(fingerprint[mid...])"
    }
}
